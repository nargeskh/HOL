open HolKernel HOLgrammars

fun ERROR f msg =
  HOL_ERR {origin_structure = "Parse",
           origin_function = f,
           message = msg};

fun munge s = String.translate (fn c => if c = #"\\" then "\\\\" else str c) s
fun quote s = "\""^munge s^"\""

datatype fixity = RF of term_grammar.rule_fixity | Prefix | Binder

val fromTGfixity = RF

val Infix = (fn (a,i) => RF (term_grammar.Infix (a,i)))
val Infixl = (fn i => Infix(LEFT, i))
val Infixr = (fn i => Infix(RIGHT, i))
fun Suffix n = RF (term_grammar.Suffix n)
val Closefix = RF term_grammar.Closefix
fun TruePrefix n = RF (term_grammar.TruePrefix n)

fun fixityToString f =
  case f of
    RF rf => "Parse.RF ("^term_grammar.rule_fixityToString rf^")"
  | Prefix => "Parse.Prefix"
  | Binder => "Parse.Binder"

(* type grammar *)
val the_type_grammar = ref parse_type.empty_grammar
val type_grammar_changed = ref false
fun type_grammar () = (!the_type_grammar)
(* term grammar *)
val the_term_grammar = ref term_grammar.stdhol
val term_grammar_changed = ref false
fun term_grammar () = (!the_term_grammar)

fun fixity s = let
  val normal = term_grammar.get_precedence (term_grammar()) s
in
  case normal of
    NONE => if Lib.mem s (term_grammar.binders (term_grammar())) then Binder
            else Prefix
  | SOME rf => RF rf
end

(* type parsing *)
fun remove_ty_aq t =
  if is_ty_antiq t then dest_ty_antiq t
  else raise ERROR "Type" "antiquotation is not of a type"
val typ1_rec = {vartype = TCPretype.Vartype, tyop = TCPretype.Tyop,
                antiq = TCPretype.fromType o remove_ty_aq}
val typ2_rec = {vartype = TCPretype.Vartype, tyop = TCPretype.Tyop,
                antiq = TCPretype.fromType}
val type_parser1 =
  ref (parse_type.parse_type typ1_rec false (!the_type_grammar))
val type_parser2 =
  ref (parse_type.parse_type typ2_rec false (!the_type_grammar))

(* pretty printing *)
val term_printer = ref (term_pp.pp_term (term_grammar()) (type_grammar()))
val type_printer = ref (type_pp.pp_type (type_grammar()))

fun update_type_fns () =
  if !type_grammar_changed then let
  in
    type_parser1 := parse_type.parse_type typ1_rec false (type_grammar());
    type_parser2 := parse_type.parse_type typ2_rec false (type_grammar());
    type_printer := type_pp.pp_type (type_grammar());
    type_grammar_changed := false
  end
  else ()

local
  (* types *)
  open parse_type
in

  fun ftoString [] = ""
    | ftoString (QUOTE s :: rest) = s ^ ftoString rest
    | ftoString (ANTIQUOTE x :: rest) = "..." ^ ftoString rest

  fun Type q = let
    val _ = update_type_fns()
    val parser = (!type_parser2)
    open optmonad monadic_parse fragstr
    infix >> >->
    val (rest, parse_result) = (parse (token (item #":") >> parser)) q
  in
    case parse_result of
      NONE => let
        val errstring =
          "Couldn't make any sense with remaining input of \"" ^ ftoString rest^"\""
      in
        raise ERROR "Type" errstring
      end
    | SOME pt => TCPretype.toType pt
  end

  fun toThyaddon s =
    {sig_ps = NONE,
     struct_ps = SOME (fn pps => Portable.add_string pps s)}


  fun == q x = Type q

  fun temp_add_type s = let
  in
    the_type_grammar := new_tyop (!the_type_grammar) s;
    type_grammar_changed := true;
    term_grammar_changed := true
  end
  fun add_type s = let
    val cmdstring = "val _ = Parse.temp_add_type \""^s^"\";"
  in
    temp_add_type s;
    adjoin_to_theory (toThyaddon cmdstring)
  end
  fun temp_add_infix_type {Name, ParseName, Assoc, Prec} = let
  in
    the_type_grammar :=
    new_binary_tyop (!the_type_grammar) {precedence = Prec,
                                         infix_form = ParseName,
                                         opname = Name,
                                         associativity = Assoc};
    type_grammar_changed := true;
    term_grammar_changed := true
  end
  fun add_infix_type (x as {Name, ParseName, Assoc, Prec}) = let
    val pname_str =
      case ParseName of
        NONE => "NONE"
      | SOME s => "SOME "^quote s
    val assocstring = assocToString Assoc
    val cmdstring =
      "val _ = Parse.temp_add_infix_type {Name = "^quote Name^", "^
      "ParseName = "^pname_str^", Assoc = "^assocstring^", "^
      "Prec = "^Int.toString Prec^"};"
  in
    temp_add_infix_type x;
    adjoin_to_theory (toThyaddon cmdstring)
  end

  fun temp_set_associativity (i,a) = let
  in
    the_term_grammar :=
    term_grammar.set_associativity_at_level (term_grammar()) (i,a);
    term_grammar_changed := true
  end

end


fun pp_type pps ty = let
  val _ = update_type_fns()
in
  Portable.add_string pps ":"; (!type_printer) pps ty
end

val type_to_string = Portable.pp_to_string 75 pp_type
fun print_type ty = Portable.output(Portable.std_out, type_to_string ty);


local
  (* terms *)
  open parse_term term_grammar

  fun mk_binder vs = let
    open Parse_support
  in
    case vs of
      SIMPLE s => make_binding_occ s
    | VPAIR(v1, v2) => let
      in
        make_vstruct [mk_binder v1, mk_binder v2] NONE
      end
    | VS_AQ x => make_aq_binding_occ x
    | TYPEDV (v, pty) => let
      in
        make_vstruct [mk_binder v] (SOME pty)
      end
    | RESTYPEDV (v, tm) =>
      raise ERROR
        "mk_binder"
        "Restricted quantifications should have been eliminated at this point"
  end

  fun toTermInEnv oinfo t = let
    open parse_term
    open Parse_support
  in
    case t of
      COMB(COMB(VAR "gspec special", t1), t2) =>
        make_set_abs (toTermInEnv oinfo t1, toTermInEnv oinfo t2)
    | COMB(t1, t2) => list_make_comb (map (toTermInEnv oinfo) [t1, t2])
    | VAR s => make_atom oinfo s
    | ABS(vs, t) => bind_term "\\" [mk_binder vs] (toTermInEnv oinfo t)
    | TYPED(t, pty) => make_constrained (toTermInEnv oinfo t) pty
    | AQ t => make_aq t
  end

  fun term_to_vs t = let
    fun ultimately s t =
      case t of
        VAR s' => s = s'
      | TYPED (t', _) => ultimately s t'
      | _ => false
  in
    case t of
      VAR s => SIMPLE s
    | TYPED (t, ty) => TYPEDV(term_to_vs t, ty)
    | AQ x => VS_AQ x
    | COMB(COMB(comma, t1), t2) =>
        if ultimately "," comma then VPAIR(term_to_vs t1, term_to_vs t2)
        else raise Fail "term not suitable as varstruct"
    | _ => raise Fail "term not suitable as varstruct"
  end

  fun reform_def (t1, t2) = let
    val v = term_to_vs t1
  in
    (v, t2)
  end handle Fail _ => let
    val (f, args) = strip_comb t1
    val newrhs = List.foldr (fn (a, body) => ABS(term_to_vs a, body)) t2 args
  in
    (term_to_vs f, newrhs)
  end

  fun munge_let binding_term body = let
    open parse_term
    fun strip_and tm acc =
      case tm of
        COMB (t1, t2) => let
        in
          case t1 of
            COMB(VAR "and", t11) => strip_and t11 (strip_and t2 acc)
          | _ => tm::acc
        end
      | _ => tm :: acc
    val binding_clauses = strip_and binding_term []
    fun is_eq tm = case tm of COMB(COMB(VAR "=", _), _) => true | _ => false
    fun dest_eq (COMB(COMB(VAR "=", t1), t2)) = (t1, t2)
      | dest_eq _ = raise Fail "(pre-)term not an equality"
    val _ =
      List.all is_eq binding_clauses orelse
      raise ERROR "Term" "let with non-equality"
    val (lhses, rhses) =
      ListPair.unzip (map (reform_def o dest_eq) binding_clauses)
    val central_abstraction = List.foldr ABS body lhses
  in
    List.foldl (fn(arg, b) => COMB(COMB(VAR "LET", b), arg))
    central_abstraction rhses
  end


  fun traverse applyp f t = let
    val traverse = traverse applyp f
  in
    if applyp t then f traverse t
    else
      case t of
        COMB(t1, t2) => COMB(traverse t1, traverse t2)
      | ABS(vs, t) => ABS(vs, traverse t)
      | TYPED(t, pty) => TYPED(traverse t, pty)
      | AQ x => AQ x
      | VAR s => VAR s
  end


  fun remove_lets t0 = let
    fun let_remove f (COMB(COMB(VAR "let", t1), t2)) = munge_let (f t1) (f t2)
      | let_remove _ _ = raise Fail "Can't happen"
    val t1 =
      traverse (fn COMB(COMB(VAR "let", _), _) => true | _ => false) let_remove
      t0
    val _ =
      traverse (fn VAR("and") => true | _ => false)
      (fn _ => raise ERROR "Term" "Invalid use of reserved word and") t1
  in
    t1
  end
in

  fun do_parse G ty = let
    open optmonad
    val pt = parse_term G ty
      handle PrecConflict(st1, st2) =>
        raise ERROR "Term"
          ("Grammar introduces precedence conflict between tokens "^
           term_grammar.STtoString G st1^" and "^
           term_grammar.STtoString G st2)
  in
    fn q => let
      val ((cs, p), _) = pt (q, PStack {lookahead = [], stack = [],
                                        in_vstruct = false})
    in
      case pstack p of
        [(NonTerminal pt, _), (Terminal BOS, _)] => let
          infix ++ >>
          val (_, res) =
            (many (fragstr.comment ++ fragstr.grab_whitespace) >>
             fragstr.eof) cs
        in
          case res of
            SOME _ => remove_specials pt
          | NONE =>
              raise ERROR "Term"
                ("Can't make sense of remaining: \""^ftoString cs)
        end
      | _ =>
          raise ERROR "Term" ("Parse failed with \""^ftoString cs^"\" remaining")
    end
  end


  val the_term_parser: (term frag list -> term parse_term.preterm) ref =
    ref (do_parse (!the_term_grammar) (!type_parser1))

  fun update_term_fns() = let
    val _ = update_type_fns()
  in
    if (!term_grammar_changed) then let
    in
      term_printer := term_pp.pp_term (term_grammar()) (type_grammar());
      the_term_parser := do_parse (!the_term_grammar) (!type_parser1);
      term_grammar_changed := false
    end
    else ()
  end

  fun pp_term pps t = let
    val _ = update_term_fns()
  in
    (!term_printer) pps t
  end
  val term_to_string = Portable.pp_to_string 75 pp_term
  fun print_term t = Portable.output(Portable.std_out, term_to_string t);

  fun parse_preTerm q = let
    val _ = update_term_fns()
    val pt0 = !the_term_parser q
  in
    remove_lets pt0
  end

  fun preTerm q = let
    val pt0 = parse_preTerm q
    val oinfo = term_grammar.overload_info (term_grammar())
  in
    Parse_support.make_preterm (toTermInEnv oinfo pt0)
  end
  fun toTerm pt = let
    val prfns = SOME(term_to_string, type_to_string)
    val oinfo = term_grammar.overload_info (term_grammar())
    open Parse_support
  in
    Preterm.typecheck prfns (make_preterm (toTermInEnv oinfo pt))
  end

  val Term = toTerm o parse_preTerm

  fun -- q x = Term q

  fun temp_add_infix(s, prec, associativity) = let
  in
    the_term_grammar :=
    add_rule (!the_term_grammar)
    {term_name = s, block_style = (AroundSamePrec, (PP.INCONSISTENT, 0)),
     fixity = Infix(associativity, prec),
     pp_elements = [HardSpace 1, RE (TOK s), BreakSpace(1,0)],
     paren_style = OnlyIfNecessary};
    term_grammar_changed := true
  end handle GrammarError s => raise ERROR "add_infix" ("Grammar Error: "^s)

  fun add_infix (s, prec, associativity) = let
    val cmdstring =
      "val _ = Parse.temp_add_infix("^quote s^", "^Int.toString prec^", "^
      assocToString associativity^");"
  in
    temp_add_infix(s,prec,associativity);
    adjoin_to_theory (toThyaddon cmdstring)
  end

  fun relToString TM = "term_grammar.TM"
    | relToString (TOK s) = "(term_grammar.TOK "^quote s^")"
  fun rellistToString [] = ""
    | rellistToString [x] = relToString x
    | rellistToString (x::xs) = relToString x ^ ", " ^ rellistToString xs
  fun block_infoToString (PP.CONSISTENT, n) =
    "(PP.CONSISTENT, "^Int.toString n^")"
    | block_infoToString (PP.INCONSISTENT, n) =
    "(PP.INCONSISTENT, "^Int.toString n^")"

  fun ParenStyleToString Always = "term_grammar.Always"
    | ParenStyleToString OnlyIfNecessary = "term_grammar.OnlyIfNecessary"
    | ParenStyleToString ParoundName = "term_grammar.ParoundName"
    | ParenStyleToString ParoundPrec = "term_grammar.ParoundPrec"

  fun BlockStyleToString AroundSameName = "term_grammar.AroundSameName"
    | BlockStyleToString AroundSamePrec = "term_grammar.AroundSamePrec"
    | BlockStyleToString AroundEachPhrase = "term_grammar.AroundEachPhrase"



  fun ppToString pp =
    case pp of
      PPBlock(ppels, bi) =>
        "term_grammar.PPBlock(["^pplistToString ppels^"], "^
        block_infoToString bi^")"
    | EndInitialBlock bi =>
        "(term_grammar.EndInitialBlock "^block_infoToString bi^")"
    | BeginFinalBlock bi =>
        "(term_grammar.BeginFinalBlock "^block_infoToString bi^")"
    | HardSpace n => "(term_grammar.HardSpace "^Int.toString n^")"
    | BreakSpace(n,m) =>
        "(term_grammar.BreakSpace("^Int.toString n^", "^
        Int.toString m^"))"
    | RE rel => "(term_grammar.RE "^relToString rel^")"
    | _ => raise Fail "Don't want to print out First or Last TM values"
  and pplistToString [] = ""
    | pplistToString [x] = ppToString x
    | pplistToString (x::xs) = ppToString x ^ ", " ^ pplistToString xs


  fun standard_spacing name fixity = let
    val bstyle = (AroundSamePrec, (PP.INCONSISTENT, 0))
    val pstyle = OnlyIfNecessary
    val pels =
      case fixity of
        RF (Infix _) => [HardSpace 1, RE (TOK name), BreakSpace(1,0)]
      | RF (TruePrefix _) => [RE(TOK name), HardSpace 1]
      | RF (Suffix _) => [HardSpace 1, RE(TOK name)]
      | RF Closefix => [RE(TOK name)] (* not sure if this will ever arise,
                                         or if it should be allowed to do so *)
      | Prefix => []
      | Binder => []
  in
    {term_name = name, fixity = fixity, pp_elements = pels,
     paren_style = pstyle, block_style = bstyle}
  end

  fun temp_add_binder(name, prec) = let
  in
    the_term_grammar :=
    term_grammar.add_binder (!the_term_grammar) (name, prec);
    term_grammar_changed := true
  end
  fun add_binder (name, prec) = let
    val cmdstring =
      "val _ = Parse.temp_add_binder("^quote name^
      ", term_grammar.std_binder_precedence);"
  in
    temp_add_binder(name, prec);
    adjoin_to_theory (toThyaddon cmdstring)
  end

  fun temp_add_rule {term_name, fixity, pp_elements, paren_style,
                     block_style} =
    case fixity of
      Prefix => ()
    | Binder => let
      in
        temp_add_binder(term_name, term_grammar.std_binder_precedence);
        term_grammar_changed := true
      end
    | RF rf => let
      in
        the_term_grammar := term_grammar.add_rule (!the_term_grammar)
        {term_name = term_name, fixity = rf, pp_elements = pp_elements,
         paren_style = paren_style, block_style = block_style};
        term_grammar_changed := true
      end

  fun add_rule (r as {term_name, fixity, pp_elements,
                      paren_style, block_style = (bs,bi)}) = let
    val cmdstring =
      "val _ = Parse.temp_add_rule{term_name = "^quote term_name^
      ", fixity = "^fixityToString fixity^ ",\n"^
      "pp_elements = ["^ pplistToString pp_elements^"],\n"^
      "paren_style = "^ParenStyleToString paren_style^",\n"^
      "block_style = ("^BlockStyleToString bs^", "^
      block_infoToString bi^")};"
  in
    temp_add_rule r;
    adjoin_to_theory (toThyaddon cmdstring)
  end

  fun temp_add_listform x = let
  in
    the_term_grammar := term_grammar.add_listform (term_grammar()) x;
    term_grammar_changed := true
  end
  fun add_listform (x as {separator,leftdelim,rightdelim,cons,nilstr}) = let
    val cmdstring =
      "val _ = Parse.temp_add_listform {separator = "^quote separator^", "^
      "leftdelim = "^quote leftdelim^", rightdelim = "^quote rightdelim^", "^
      "cons = "^quote cons^", nilstr = "^quote nilstr^"};"
  in
    temp_add_listform x;
    adjoin_to_theory (toThyaddon cmdstring)
  end

  fun temp_add_numeral_form x = let
  in
    the_term_grammar := term_grammar.add_numeral_form (term_grammar()) x;
    term_grammar_changed := true
  end
  fun add_numeral_form (c, stropt) = let
    val cmdstring =
      "val _ = Parse.temp_add_numeral_form (#\""^str c^"\", "^
      (case stropt of NONE => "NONE" | SOME s => "SOME "^quote s)^");"
  in
    temp_add_numeral_form (c, stropt);
    adjoin_to_theory (toThyaddon cmdstring)
  end

  fun temp_give_num_priority c = let
  in
    the_term_grammar := term_grammar.give_num_priority (term_grammar()) c;
    term_grammar_changed := true
  end
  fun give_num_priority c = let
    val cmdstring =
      "val _ = Parse.temp_give_num_priority #\""^str c^"\";"
  in
    temp_give_num_priority c;
    adjoin_to_theory (toThyaddon cmdstring)
  end

  fun temp_remove_numeral_form c = let
  in
    the_term_grammar := term_grammar.remove_numeral_form (term_grammar()) c;
    term_grammar_changed := true
  end
  fun remove_numeral_form c = let
    val cmdstring =
      "val _ = Parse.temp_remove_numeral_form #\""^str c^"\";"
  in
    temp_remove_numeral_form c;
    adjoin_to_theory (toThyaddon cmdstring)
  end


  fun temp_associate_restriction (bs, s) = let
    val lambda = #lambda (specials (term_grammar()))
    val b = if lambda = bs then LAMBDA else BinderString bs
  in
    the_term_grammar :=
    term_grammar.associate_restriction (term_grammar()) (b, s);
    term_grammar_changed := true
  end

  fun associate_restriction (bs, s) = let
    val cmdstring =
      "val _ = Parse.temp_associate_restriction ("^quote bs^", "^quote s^")"
  in
    temp_associate_restriction (bs, s);
    adjoin_to_theory (toThyaddon cmdstring)
  end


  fun temp_remove_term s = let
  in
    the_term_grammar := term_grammar.remove_standard_form (term_grammar()) s;
    term_grammar_changed := true
  end
  fun remove_term s = let
    val cmdstring = "val _ = Parse.temp_remove_term "^quote s^";"
  in
    temp_remove_term s;
    adjoin_to_theory (toThyaddon cmdstring)
  end

  fun temp_remove_termtok r = let
  in
    the_term_grammar := term_grammar.remove_form_with_tok (term_grammar()) r;
    term_grammar_changed := true
  end
  fun remove_termtok (r as {term_name, tok}) = let
    val cmdstring =
      "val _ = Parse.remove_termtok {term_name = "^quote term_name^", "^
      "tok = "^quote tok^"};"
  in
    temp_remove_termtok r;
    adjoin_to_theory (toThyaddon cmdstring)
  end

  fun temp_set_fixity s f = let
  in
    remove_termtok {term_name = s, tok = s};
    temp_add_rule (standard_spacing s f)
  end
  fun set_fixity s f = let
    val cmdstring =
      "val _ = Parse.temp_set_fixity "^quote s^" ("^fixityToString f^");"
  in
    temp_set_fixity s f;
    adjoin_to_theory (toThyaddon cmdstring)
  end



  fun temp_prefer_form_with_tok r = let
  in
    the_term_grammar := term_grammar.prefer_form_with_tok (term_grammar()) r;
    term_grammar_changed := true
  end
  fun prefer_form_with_tok (r as {term_name,tok}) = let
    val cmdstring =
      "val _ = Parse.temp_prefer_form_with_tok {term_name = "^quote term_name^
      ", tok = "^quote tok^"}";
  in
    temp_prefer_form_with_tok r;
    adjoin_to_theory (toThyaddon cmdstring)
  end

  fun temp_clear_prefs_for_term s = let
  in
    the_term_grammar := term_grammar.clear_prefs_for s (term_grammar());
    term_grammar_changed := true
  end
  fun clear_prefs_for_term s = let
    val cmdstring = "val _ = Parse.temp_clear_prefs_for_term "^quote s^";"
  in
    temp_clear_prefs_for_term s;
    adjoin_to_theory (toThyaddon cmdstring)
  end

  (* overloading *)
  fun temp_allow_for_overloading_on (s, ty) = let
  in
    the_term_grammar :=
    term_grammar.fupdate_overload_info (Overload.add_overloaded_form s ty)
    (term_grammar());
    term_grammar_changed := true
  end
  fun allow_for_overloading_on (s, ty) = let
    val tystring =
      Portable.pp_to_string 75 (TheoryPP.print_type_to_SML "mkV" "mkT") ty
    val cmdstring = String.concat [
      "val _ = let fun mkV s = Type.mk_vartype s\n",
      "    fun mkT s args = Type.mk_type{Tyop = s, Args = args}\n",
      "    val ty = ",tystring,"\n",
      "in  Parse.temp_allow_for_overloading_on (", quote s, ", ty) end\n"
                                   ]
  in
    temp_allow_for_overloading_on (s, ty);
    adjoin_to_theory (toThyaddon cmdstring)
  end
  fun temp_overload_on (s, t) =
    if (not (is_const t)) then
      print "Can't have non-constants as targets of overloading."
    else let
      val {Name,Ty} = dest_const t
    in
      the_term_grammar :=
      term_grammar.fupdate_overload_info
      (Overload.add_actual_overloading {opname = s, realname = Name,
                                        realtype = Ty}) (term_grammar());
      term_grammar_changed := true
    end

  fun overload_on (s, t) = let
    val {Name, Ty} = dest_const t
      handle HOL_ERR _ =>
        raise ERROR "overload_on"
          "Can't have non-constants as targets of overloading"
    val tystring =
      Portable.pp_to_string 75 (TheoryPP.print_type_to_SML "mkV" "mkT") Ty
    val cmdstring = String.concat
      [
       "val _ = let fun mkV s = Type.mk_vartype s\n",
       "    fun mkT s args = Type.mk_type{Tyop = s, Args = args}\n",
       "    val ty = ",tystring,"\n",
       "    val tm = Term.mk_const{Name = ", quote Name,",\n",
       "                           Ty = ty}\n",
       "in  Parse.overload_on (", quote s, ", tm) end\n"
       ]
  in
    temp_overload_on (s,t);
    adjoin_to_theory (toThyaddon cmdstring)
  end

  fun temp_clear_overloads_on s = let
  in
    the_term_grammar := term_grammar.fupdate_overload_info
    (Overload.remove_overloaded_form s) (term_grammar());
    term_grammar_changed := true
  end
  fun clear_overloads_on s = let
    val cmdstring = "val _ = Parse.temp_clear_overloads_on "^quote s^";\n"
  in
    temp_clear_overloads_on s;
    adjoin_to_theory (toThyaddon cmdstring)
  end


  fun pp_thm ppstrm th = let
    open Portable
    fun repl ch alist =
      String.implode (itlist (fn _ => fn chs => (ch::chs)) alist [])
    val {add_string,add_break,begin_block,end_block,...} = with_ppstream ppstrm
    val pp_term = pp_term ppstrm
    fun pp_terms b L =
      (begin_block INCONSISTENT 1; add_string "[";
       if b then pr_list pp_term
         (fn () => add_string ",")
         (fn () => add_break(1,0)) L
       else add_string (repl #"." L); add_string "]";
         end_block())
  in
    begin_block INCONSISTENT 0;
    if (!Globals.max_print_depth = 0) then add_string " ... "
    else
      (case (tag th, hyp th, !Globals.show_tags, !Globals.show_assums) of
         (tg, asl, st, sa)  =>
           if (not st andalso not sa andalso null asl) then ()
           else (if st then Tag.pp ppstrm tg else ();
                   add_break(1,0);
                   pp_terms sa asl; add_break(1,0));
             add_string "|- "; pp_term (concl th)
             );
         end_block()
  end;

  fun thm_to_string thm =
    Portable.pp_to_string (!Globals.linewidth) pp_thm thm;

  fun print_thm thm = Portable.output(Portable.std_out, thm_to_string thm);

  fun pp_with_bquotes ppfn pp x = let
    open Portable
  in
    add_string pp "`"; ppfn pp x; add_string pp "`"
  end


end

(* definitional principles with parse impact *)
fun atom_name t =
  #Name (dest_var t) handle HOL_ERR _ => #Name (dest_const t)
fun get_head_tm t = #1 (strip_comb (lhs (#2 (strip_forall t))))

fun new_infixr_definition (s, t, p) = let
  val res = new_definition(s, t)
  val t_name = atom_name (get_head_tm t)
in
  add_infix(t_name, p, RIGHT);
  res
end
fun new_infixl_definition (s, t, p) = let
  val res = new_definition(s, t)
  val t_name = atom_name (get_head_tm t)
in
  add_infix(t_name, p, LEFT);
  res
end

fun new_binder_definition (s, t) = let
  val res = new_definition(s, t)
  val t_name = atom_name (get_head_tm t)
in
  add_binder (t_name, term_grammar.std_binder_precedence);
  res
end

fun new_infix{Name, Ty, Prec} = let
  val res = new_constant{Name = Name, Ty = Ty}
in
  add_infix(Name, Prec, RIGHT);
  res
end

fun new_binder {Name, Ty} = let
  val res = new_constant{Name = Name, Ty = Ty}
in
  add_binder (Name, term_grammar.std_binder_precedence); res
end

fun new_type{Name,Arity} = let
  val res = Theory.new_type{Name = Name, Arity = Arity}
in
  add_type Name;
  res
end

fun new_infix_type (x as {Name,Arity,ParseName,Prec,Assoc}) = let
  val _ = Arity = 2 orelse
    raise ERROR "new_infix_type" "Infix types must have arity 2"
  val res = Theory.new_type{Name = Name, Arity = Arity}
in
  add_infix_type {Name = Name, ParseName = ParseName,
                  Prec = Prec, Assoc = Assoc} ;
  res
end

fun new_type_definition (x as {name, inhab_thm, pred}) = let
  val res = Type_def.new_type_definition x
in
  add_type name;
  res
end

fun new_gen_definition (s, t, f) = let
  val t_name = atom_name (get_head_tm t)
in
  new_definition(s,t) before
  add_rule(standard_spacing t_name f)
end

fun new_specification {name,sat_thm,consts} = let
  fun foldfn ({const_name, fixity}, (ncs, cfs)) =
    (const_name::ncs, (const_name, fixity) :: cfs)
  val (newconsts, consts_with_fixities) = List.foldl foldfn ([],[]) consts
  val res =
    Const_spec.new_specification
    {name = name, sat_thm = sat_thm, consts = List.rev newconsts}
  fun do_parse_stuff (name, fixity) = add_rule(standard_spacing name fixity)
in
  app do_parse_stuff consts_with_fixities;
  res
end

fun new_theory s = Theory.new_theory0 (SOME pp_thm) s
fun export_theory () = Theory.export_theory0 (SOME pp_thm)
fun print_theory () = Theory.print_theory0 {pp_thm = pp_thm, pp_type = pp_type}

(* constrain parsed term to have a given type *)
fun typedTerm qtm ty =
   let fun trail s = [QUOTE (s^"):"), ANTIQUOTE(Term.ty_antiq ty), QUOTE""]
   in
   Term (case (Lib.front_last qtm)
        of ([],QUOTE s) => trail ("("^s)
         | (QUOTE s::rst, QUOTE s') => (QUOTE ("("^s)::rst) @ trail s'
         | _ => raise ERROR"typedTerm" "badly formed quotation")
   end;

val hide = Parse_support.hide
val reveal = Parse_support.reveal
val hidden = Parse_support.hidden

(* pp_element values that are brought across from term_grammar *)
val TM = term_grammar.RE term_grammar.TM
val TOK = term_grammar.RE o term_grammar.TOK

val BreakSpace = term_grammar.BreakSpace
val HardSpace = term_grammar.HardSpace
val PPBlock = term_grammar.PPBlock

val OnlyIfNecessary = term_grammar.OnlyIfNecessary
val ParoundName = term_grammar.ParoundName

val AroundSamePrec = term_grammar.AroundSamePrec
val AroundSameName = term_grammar.AroundSameName
val AroundEachPhrase = term_grammar.AroundEachPhrase
val BeginFinalBlock = term_grammar.BeginFinalBlock
val EndInitialBlock = term_grammar.EndInitialBlock