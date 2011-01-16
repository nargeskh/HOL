(* Copyright (c) 2010 Tjark Weber. All rights reserved. *)

(* QBF certificates and proof reconstruction.

   As defined in "A File Format for QBF Certificates" by Daniel Kroening and
   Christoph M. Wintersteiger (2007-05-01, available at
   http://www.cprover.org/qbv/download/qbcformat.pdf).

   Also see "A First Step Towards a Unified Proof Checker for QBF" by Toni
   Jussila, Armin Biere, Carsten Sinz, Daniel Kröning and Christoph
   Wintersteiger, published at SAT 2007 (vol. 4501 of LNCS).

   We additionally require that certificates of validity contain "extensions"
   only, and that certificates of invalidity contain "resolutions" only (as
   defined in the first paper above).
*)

structure QbfCertificate =
struct

  val ERR = Feedback.mk_HOL_ERR "QbfCertificate"

(* ------------------------------------------------------------------------- *)
(* The type of QBF certificates.                                             *)
(* ------------------------------------------------------------------------- *)

  type cindex = int  (* clause index, must be >= 1 *)
  type vindex = int  (* variable index, must be >= 1 *)
  type literal = int  (* a possibly negated variable index, must be <> 0 *)

  datatype extension = ITE of literal * literal * literal
                     | AND of literal list

  type resolution = literal list * cindex list

  datatype certificate =
      VALID of (vindex, extension) Redblackmap.dict
        * (vindex, literal) Redblackmap.dict
    | INVALID of (cindex, resolution) Redblackmap.dict * cindex

(* ------------------------------------------------------------------------- *)
(* read_certificate_file: reads a QBF certificate from a file                *)
(* ------------------------------------------------------------------------- *)

  (* This would arguably be much nicer to implement with parser combinators.
     Or perhaps one should use mllex/mlyacc. *)

  fun read_certificate_file path =
  let
    (* string list -> string list *)
    fun filter_header ("QBCertificate\n" :: lines) =
      lines
      | filter_header _ =
      raise ERR "read_certificate_file" "'QBCertificate' header not found"
    (* string -> int *)
    fun int_from_string s =
      case Int.fromString s of
        NONE =>
        raise ERR "read_certificate_file"
          ("integer expected ('" ^ s ^ "' found)")
      | SOME i =>
        i
    (* literal list -> string list -> literal list *)
    fun extension_lits lits ["0"] =
      List.rev lits
      | extension_lits _ ("0" :: _) =
      raise ERR "read_certificate_file"
        "unexpected input after '0'-terminated list of extension literals"
      | extension_lits _ [] =
      raise ERR "read_certificate_file"
        "missing '0' terminator after extension literals"
      | extension_lits lits (literal :: xs) =
      extension_lits (int_from_string literal :: lits) xs
    (* (vindex, extension) dict -> string list -> (vindex, extension) dict *)
    fun extension ext [vindex, "I", lit1, lit2, lit3] =
      Redblackmap.insert (ext, int_from_string vindex,
        ITE (int_from_string lit1, int_from_string lit2, int_from_string lit3))
      | extension ext (vindex :: "A" :: lits) =
      Redblackmap.insert (ext, int_from_string vindex,
        AND (extension_lits [] lits))
      | extension _ _ =
      raise ERR "read_certificate_file" "extension: invalid format"
    (* cindex list -> string list -> cindex list *)
    fun resolution_clauses clauses ["0"] =
        List.rev clauses
      | resolution_clauses clauses ("0" :: _) =
        raise ERR "read_certificate_file"
          "unexpected input after '0'-terminated list of clauses"
      | resolution_clauses clauses (cindex :: xs) =
        resolution_clauses (int_from_string cindex :: clauses) xs
      | resolution_clauses _ [] =
      raise ERR "read_certificate_file"
        "resolution: '0' expected to terminate list of clauses"
    (* literal list -> string list -> resolution *)
    fun resolution_args [] ("*" :: xs) =
        ([], resolution_clauses [] xs)
      | resolution_args _ ("*" :: _) =
        raise ERR "read_certificate_file"
          "resolution: '*' found after list of literals (use '0' instead)"
      | resolution_args lits ("0" :: xs) =
        (List.rev lits, resolution_clauses [] xs)
      | resolution_args lits (lit :: xs) =
        resolution_args (int_from_string lit :: lits) xs
      | resolution_args _ [] =
        raise ERR "read_certificate_file"
          "resolution: missing '*' or '0' terminator"
    (* (cindex, resolution) dict -> string list -> (cindex, resolution) dict *)
    fun resolution res (cindex :: xs) =
      Redblackmap.insert (res, int_from_string cindex, resolution_args [] xs)
      | resolution _ _ =
      raise ERR "read_certificate_file" "resolution: clause index expected"
    (* (vindex, literal) dict -> string list -> (vindex, literal) dict *)
    fun valid_conclusion dict [] =
      dict
      | valid_conclusion dict (vindex :: literal :: xs) =
      valid_conclusion (Redblackmap.insert
        (dict, int_from_string vindex, int_from_string literal)) xs
      | valid_conclusion _ _ =
      raise ERR "read_certificate_file"
        "vindex/literal pair expected in conclusion"
    (* (vindex, extension) dict * (cindex, resolution) dict -> string list ->
         conclusion *)
    fun conclusion (ext, res) ("VALID" :: xs) =
      let
        val _ = Redblackmap.isEmpty res orelse
          raise ERR "read_certificate_file"
            "conclusion is 'VALID', but there are resolutions"
      in
        VALID (ext, valid_conclusion (Redblackmap.mkDict Int.compare) xs)
      end
      | conclusion (ext, res) ["INVALID", cindex] =
      let
        val _ = Redblackmap.isEmpty ext orelse
          raise ERR "read_certificate_file"
            "conclusion is 'INVALID', but there are extensions"
      in
        INVALID (res, int_from_string cindex)
      end
      | conclusion _ _ =
      raise ERR "read_certificate_file" "conclusion: invalid format"
    (* (vindex, extension) dict * (cindex, resolution) dict -> string list list
         -> certificate *)
    fun certificate (ext, res) ["CONCLUDE" :: xs] =
        conclusion (ext, res) xs
      | certificate _ (("CONCLUDE" :: _) :: _) =
        raise ERR "read_certificate_file" "unexpected input after conclusion"
      | certificate (ext, res) (("E" :: xs) :: xss) =
      certificate (extension ext xs, res) xss
      | certificate (ext, res) (xs :: xss) =
      certificate (ext, resolution res xs) xss
      | certificate _ [] =
        raise ERR "read_certificate_file" "missing conclusion"
  in
    (certificate
       (Redblackmap.mkDict Int.compare, Redblackmap.mkDict Int.compare)
    o (map (String.tokens (Lib.C Lib.mem [#" ", #"\t", #"\n"])))
    o filter_header
    o List.filter (fn l => l <> "\n")
    o QbfLibrary.read_lines_from_file) path
  end

(* ------------------------------------------------------------------------- *)
(* check: proves or disproves the QBF 't' (see QDimacs.sml for the format of *)
(*      QBFs), using an appropriate certificate.  Returns either "|- t" (if  *)
(*      the certificate is 'VALID ...') or "t |- F" (if the certificate is   *)
(*      'INVALID ...').  Fails if 't' is not a QBF, or if the certificate is *)
(*      not suitable for 't'.                                                *)
(* ------------------------------------------------------------------------- *)

  local open Term Redblackset in
    (* h is the hypothesis defining an existential variable.
         for original variables, this is (v = e) for some extension variable e.
         for extension variables, this is (e = tm) for some extension term tm.
       lhs is the index of the variable on the left of an hypothesis
       rhs is the set of indexes of variables occurring on the right.
         for a universally quantified variable, lhs is just its index.
       pos is the number of quantifiers before a variable is bound in the original term.
         for extension variables, pos is NONE.  *)
    datatype vtype = Forall of {v:term, lhs:vindex, pos:int}
                   | Exists of {h:term, lhs:vindex, rhs:vindex set, pos:int option}

    (* R x y means x should be bound in scope of y (i.e. x has more quantifiers before it)
       This is either because this was the case in the original term,
       or because we need to remove the hypothesis (x = tx) (and quantify over x)
       before we can quantify over y, because y occurs in tx *)
    fun R (Forall {pos=n1,...}) (Forall {pos=n2,...}) = n1 > n2
      | R (Forall {pos=n1,...}) (Exists {pos=SOME n2,...}) = n1 > n2
      | R (Exists {pos=SOME n1,...}) (Forall {pos=n2,...}) = n1 > n2
      | R (Exists {pos=SOME n1,...}) (Exists {pos=SOME n2,...}) = n1 > n2
      | R (Exists {rhs,...}) (Forall {lhs,...}) = member(rhs,lhs)
      | R (Exists {rhs,...}) (Exists {lhs,...}) = member(rhs,lhs)
      | R _ _ = false
  end

  fun check t dict (VALID (exts,lits)) = let
    open Lib Thm Drule Term Type boolSyntax
    open Redblackset Redblackmap

    val (var_to_index, index_to_var) = let
      open String Int Option
      val s = "v"  (*TODO*)
      fun num_to_var n = mk_var(s^(toString n),bool)
      (* in this case we use the inverse of dict to
         map indexes to variables, but since dict only
         binds original variables, we update the inverse map
         on indexes of extension variables as necessary,
         (using num_to_var for extensions) *)
      fun invert_dict d =
        foldl (fn(v,n,d)=>insert(d,n,v)) (mkDict compare) d
      val tcid = ref (invert_dict dict)
      fun update (n,v) = (tcid := insert(!tcid,n,v); v)
    in
      (curry find dict,
       fn n => find (!tcid,n)
         handle NotFound => update (n,num_to_var n))
    end

    (* Traverse the prefix of the term and
       calculate vtypes for all the bound variables.
       Return a list of vtypes, the matrix, and a new lits map.
       The new lits map binds any existential variables that were
         not bound to explicit witness literals to 0,
         indicating that they should be set to true.
       The hypotheses for the existential variables are of the form
         (v = e), where e is the corresponding extension variable,
         or (v = T) when there is none.
       The rhs (dependency) sets for the existential variables
         are either {e} or {}.  *)
    val (vars,mat,lits) = let
      val cmp = Int.compare
      fun enum vars t lits' n = let
        val ((v,t), is_forall) = (dest_forall t, true)
          handle Feedback.HOL_ERR _ => (dest_exists t, false)
        val lhs = var_to_index v
        val (var,lits') =
          if is_forall then (Forall {v=v,lhs=lhs,pos=n}, lits') else let
            val (tm,rhs,lits') = let
              val ext_lit = find(lits,lhs)
              val ext_index = Int.abs ext_lit
              val tm = index_to_var ext_index
              val tm = if ext_lit < 0 then mk_neg tm else tm
              val rhs = singleton cmp ext_index
            in (tm,rhs,lits') end
            handle NotFound => (T,empty cmp,insert(lits',lhs,0))
          in (Exists {h=mk_eq(v,tm),lhs=lhs,rhs=rhs,pos=SOME n}, lits') end
      in enum (var::vars) t lits' (n+1) end
      handle Feedback.HOL_ERR _ => (vars,t,lits')
    in enum [] t lits 0 end

    (* add all the hypotheses for the original existential variables
       onto the front of the matrix, so we end up with
       (v1 = e1) ==> (v2 = e2) ==> ... ==> mat *)
    fun foldthis (Forall _,t) = t
      | foldthis (Exists {h,...},t) = mk_imp(h,t)
    val mat = Profile.profile "mk_imp" (List.foldl foldthis mat) vars

    (* extension_to_term calculates a term corresponding
         to the definition of an extension variable,
         plus the set of indexes that term depends on.
       If an extension is defined using an original existential variable v,
       replace references to v by references to v's witness (extension) variable.
       If v has no witness, replace references to v by references to T,
       but simplify as necessary.
       For example, if v has no witness:
         if v occurs in an AND, don't bother listing it.
         if ~v occurs in an AND, replace the AND by F,
         if v is the test in an ITE, replace the ITE by its consequent
         etc. *)
    local
      val empty = empty Int.compare
      (* lit processes a literal l, accumulating dependencies in s.
         TFk is the continuation for when l has no witness.
           TFk is passed whether l was not negated
           (i.e. will be constant T, rather than constant F)
         vk is the continuation for when l has a witness.
           vk is passed the literal of the witness,
             and s with the index of the witness added *)
      fun lit (l,s) TFk vk = let
        val index = Int.abs l
      in let
        val el = find(lits,index)
      in if el = 0 then TFk (l > 0) else let
        val ext_index = Int.abs el
        val s = add(s,ext_index)
        val v = index_to_var ext_index
        val neg = if l < 0 then el > 0 else el < 0
        val v = if neg then mk_neg v else v
      in vk (v,s) end end
      handle NotFound => let
        val s = add(s,index)
        val v = index_to_var index
        val v = if l < 0 then mk_neg v else v
      in vk (v,s) end end
      exception False
      fun afold (l,(t,s)) = lit (l,s)
        (fn true=>(t,s)|false=>raise False)
        (fn(v,s)=>
         (case t of NONE   => SOME v
                  | SOME t => SOME (mk_conj(v,t)), s))
      fun negate t =
        dest_neg t handle Feedback.HOL_ERR _ => mk_neg t
    in
      fun extension_to_term (AND ls) =
      (let
            val (t,s) = List.foldl afold (NONE,empty) ls
          in case t of NONE   => (T,s)
                     | SOME t => (t,s)
          end handle False => (F,empty))
        | extension_to_term (ITE(t,c,a)) =
          lit (t,empty)
              (fn t=> lit (if t then c else a,empty)
                      (fn true=>(T,empty)|false=>(F,empty))
                      (fn(v,s)=>(v,s)))
              (fn(t,s)=> lit (c,s)
                         (fn c=> lit (a,s)
                                 (fn a=>(if c then if a then T else t
                                              else if a then negate t else F,
                                         s))
                                 (fn(a,s)=>(if c then mk_disj(t,a)
                                                 else mk_conj(negate t,a),s)))
                         (fn(c,s)=> lit (a,s)
                                    (fn a=>((if a then mk_imp else mk_conj)(t,c),s))
                                    (fn(a,s)=>(mk_cond(t,c,a),s))))
    end

    (* calculate vtypes for the extension variables,
       add the hypotheses to the matrix,
       and add the vtypes to the list of vtypes *)
    fun foldthis (lhs,ext,(t,vars)) = let
      val v = index_to_var lhs
      val (tm,rhs) = extension_to_term ext
      val h = mk_eq(v,tm)
      val var = Exists {h=h,lhs=lhs,rhs=rhs,pos=NONE}
    in (mk_imp(h,t),var::vars) end
    val (mat,vars) = Profile.profile "mat_vars" (foldl foldthis (mat,vars)) exts

    val thm = Profile.profile "SAT_PROVE" HolSatLib.SAT_PROVE mat

    val vars = Profile.profile "topsort" (Lib.topsort R) vars

    (* Discharge the hypotheses of the proved theorem
       in the right order to recover the original term
       as its conclusion.
       This order is calculated in the topsort above.
       Specifically, generalize universal variables,
       use EXISTS on existential variables, and
       use INST, REFL, and PROVE_HYP to remove the hypotheses *)
    fun foldthis ((Forall {v,...}),th) = Profile.profile "Forall" (GEN v) th
      | foldthis ((Exists {h,pos,...}),th) = Profile.profile "Exists" (fn () => let
        val (v,w) = dest_eq h
        val th = if Option.isSome pos then EXISTS (mk_exists(v,concl th),v) th else th
        val th = INST [v |-> w] th
        val th = PROVE_HYP (REFL w) th
      in th end) ()
    val thm = Profile.profile "DISCH_ALL" DISCH_ALL (List.foldl foldthis (Profile.profile "UNDISCH_ALL" UNDISCH_ALL thm) vars)

      (* sanity checks *)
      val _ = if !QbfTrace.trace < 1 orelse HOLset.isEmpty (Thm.hypset thm) then
          ()
        else
          Feedback.HOL_WARNING "QbfCertificate" "check" "final theorem has hyps"
      val _ = if !QbfTrace.trace < 1 orelse Term.aconv (Thm.concl thm) t then
          ()
        else
          Feedback.HOL_WARNING "QbfCertificate" "check"
            "final theorem proves a different term"
    in
      thm
    end
(* ------------------------------------------------------------------------- *)
    | check t _ (INVALID (dict, cindex)) =
    let
      (* pre-processing: break the problem apart into clauses in sequent form
         suitable for Q-resolution *)

      (* We assume that there are no free variables in 't', so that *all*
         variables in the matrix occur in 'vars'. *)
      val (_, vars, matrix) = QbfLibrary.enumerate_quantified_vars t

      (* a dictionary that maps each variable to a pair, which consists of the
         variable's index and a Boolean that is true if the variable is
         universally quantified, and false if it is existentially quantified *)
      val var_dict = List.foldl (fn ((i, var, is_forall), var_dict) =>
        Redblackmap.insert (var_dict, var, (i, is_forall)))
        (Redblackmap.mkDict Term.var_compare) vars
      fun index_fn var =
        Redblackmap.find (var_dict, var)

      val vars = List.rev vars
      fun foldthis (clause, (i, clause_dict)) =
        let
          val clause = QbfLibrary.CLAUSE_TO_SEQUENT clause
          val lits = QbfLibrary.literals_in_clause index_fn clause
        in
          (i + 1, Redblackmap.insert (clause_dict, i,
            QbfLibrary.forall_reduce (clause, vars, matrix, lits)))
        end

      (* a dictionary that maps each clause identifier to a 4-tuple, which
         consists of 1. the clause theorem (in sequent form, cf.
         'QbfLibrary.CLAUSE_TO_SEQUENT'), 2. the list of missing variables (cf.
         'QbfLibrary.enumerate_quantified_vars', 3. the hypothesis (initially,
         this is 'matrix'), and 4. the list of literals in the clause (cf.
         'QbfLibrary.literals_in_clause' *)
      val clause_dict = Lib.snd (List.foldl foldthis
        (1, Redblackmap.mkDict Int.compare)
        (Drule.CONJUNCTS (Thm.ASSUME matrix)))

      (* depth-first recursion over the certificate (which represents a DAG),
         using QRESOLVE_CLAUSES to derive new clauses from existing ones *)
      fun derive (c_dict, index) =
        case Redblackmap.peek (c_dict, index) of
          SOME clause =>
          (c_dict, clause)
        | NONE =>
          let
            val (_, indices) = Redblackmap.find (dict, index)
              handle Redblackmap.NotFound =>
                raise ERR "check"
                  ("invalid certificate: no definition for clause ID " ^
                   Int.toString index)
            val _ = if List.null indices then
                raise ERR "check"
                  ("invalid certificate: empty definition for clause ID " ^
                     Int.toString index)
              else ()
            val (c_dict, clauses) = Lib.foldl_map derive (c_dict, indices)
            val clause = List.foldl (QbfLibrary.QRESOLVE_CLAUSES)
              (List.hd clauses) (List.tl clauses)
          in
            (Redblackmap.insert (c_dict, index, clause), clause)
          end

      (* derive "t |- F", using the certificate *)
      val thm = #1 (Lib.snd (derive (clause_dict, cindex)))

      (* sanity checks *)
      val _ = if !QbfTrace.trace < 1 orelse
          (HOLset.numItems (Thm.hypset thm) = 1 andalso
            HOLset.member (Thm.hypset thm, t)) then
          ()
        else
          Feedback.HOL_WARNING "QbfCertificate" "check" "final theorem has hyps"
      val _ = if !QbfTrace.trace < 1 orelse
        Term.aconv (Thm.concl thm) boolSyntax.F then
          ()
        else
          Feedback.HOL_WARNING "QbfCertificate" "check" "final theorem not F"
    in
      thm
    end
end
