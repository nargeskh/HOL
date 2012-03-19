open HolKernel bossLib Theory Parse Tactic boolLib Lib

val _ = new_theory "example_rc6";

open wordsTheory wordsLib arithmeticTheory listTheory;
open RC6Theory;

open ml_translatorTheory ml_translatorLib;

val RC6_def = save_thm("RC6_def", RC6_def);
val RC6_CORRECT = save_thm("RC6_CORRECT",RC6_CORRECT);


(* translations *)

fun find_def tm = let
  val thy = #Thy (dest_thy_const tm)
  val name = #Name (dest_thy_const tm)
  in fetch thy (name ^ "_def") handle HOL_ERR _ =>
     fetch thy (name ^ "_DEF") handle HOL_ERR _ =>
     fetch thy (name)
  end


(* words *)

val WORD_def = Define `WORD w = NUM (w2n w)`;

val _ = add_type_inv (inst [alpha|->``:32``] ``WORD``)
val _ = add_type_inv (inst [alpha|->``:16``] ``WORD``)
val _ = add_type_inv (inst [alpha|->``:8``] ``WORD``)

val EqualityType_WORD = prove(
  ``EqualityType WORD``,
  EVAL_TAC THEN SRW_TAC [] [] THEN EVAL_TAC)
  |> store_eq_thm;

val Eval_w2n_word32 = prove(
  ``!v. ((NUM --> NUM) (\x.x)) v ==> ((WORD --> NUM) (w2n:word32->num)) v``,
  SIMP_TAC std_ss [Arrow_def,AppReturns_def,WORD_def])
  |> MATCH_MP (MATCH_MP Eval_WEAKEN (hol2deep ``\x.x:num``))
  |> store_eval_thm;

val Eval_w2n_word16 = prove(
  ``!v. ((NUM --> NUM) (\x.x)) v ==> ((WORD --> NUM) (w2n:word16->num)) v``,
  SIMP_TAC std_ss [Arrow_def,AppReturns_def,WORD_def])
  |> MATCH_MP (MATCH_MP Eval_WEAKEN (hol2deep ``\x.x:num``))
  |> store_eval_thm;

val Eval_w2n_word8 = prove(
  ``!v. ((NUM --> NUM) (\x.x)) v ==> ((WORD --> NUM) (w2n:word8->num)) v``,
  SIMP_TAC std_ss [Arrow_def,AppReturns_def,WORD_def])
  |> MATCH_MP (MATCH_MP Eval_WEAKEN (hol2deep ``\x.x:num``))
  |> store_eval_thm;

val Eval_n2w_word32 = prove(
  ``!v. ((NUM --> NUM) (\x.x MOD 4294967296)) v ==> ((NUM --> WORD) (n2w:num->word32)) v``,
  SIMP_TAC (srw_ss()) [Arrow_def,AppReturns_def,WORD_def,w2n_n2w])
  |> MATCH_MP (MATCH_MP Eval_WEAKEN (hol2deep ``\x.x MOD 4294967296``))
  |> store_eval_thm;

val Eval_n2w_word16 = prove(
  ``!v. ((NUM --> NUM) (\x.x MOD 65536)) v ==> ((NUM --> WORD)
  (n2w:num->word16)) v``,
  SIMP_TAC (srw_ss()) [Arrow_def,AppReturns_def,WORD_def,w2n_n2w])
  |> MATCH_MP (MATCH_MP Eval_WEAKEN (hol2deep ``\x.x MOD 65536``))
  |> store_eval_thm;

val Eval_n2w_word8 = prove(
  ``!v. ((NUM --> NUM) (\x.x MOD 256)) v ==> ((NUM --> WORD) (n2w:num->word8)) v``,
  SIMP_TAC (srw_ss()) [Arrow_def,AppReturns_def,WORD_def,w2n_n2w])
  |> MATCH_MP (MATCH_MP Eval_WEAKEN (hol2deep ``\x.x MOD 256``))
  |> store_eval_thm;

val res = translate (word_add_def |> INST_TYPE [alpha|->``:32``]);
val res = translate (word_mul_def |> INST_TYPE [alpha|->``:32``]);
val res = translate (word_add_def |> INST_TYPE [alpha|->``:16``]);
val res = translate (word_mul_def |> INST_TYPE [alpha|->``:16``]);
val res = translate (word_add_def |> INST_TYPE [alpha|->``:8``]);
val res = translate (word_mul_def |> INST_TYPE [alpha|->``:8``]);
val res = translate EXP
val res = translate (find_def ``DIV_2EXP``)
val res = translate (find_def ``MOD_2EXP``)
val res = translate (find_def ``BITS``)
val res = translate (find_def ``BIT``)
val res = translate (find_def ``SBIT``)
val res = translate (find_def ``BITWISE``)

val word_xor_lemma = prove(
  ``!w v:word32. w ?? v = n2w (BITWISE 32 (\x y. x <> y) (w2n w) (w2n v))``,
  REPEAT Cases THEN FULL_SIMP_TAC (srw_ss()) [word_xor_n2w]);

val word_xor_lemma16 = prove(
  ``!w v:word16. w ?? v = n2w (BITWISE 16 (\x y. x <> y) (w2n w) (w2n v))``,
  REPEAT Cases THEN FULL_SIMP_TAC (srw_ss()) [word_xor_n2w]);

val word_xor8_lemma = prove(
  ``!w v:word8. w ?? v = n2w (BITWISE 8 (\x y. x <> y) (w2n w) (w2n v))``,
  REPEAT Cases THEN FULL_SIMP_TAC (srw_ss()) [word_xor_n2w]);

val res = translate word_xor_lemma
val res = translate word_xor_lemma16
val res = translate word_xor8_lemma

val word_or_lemma = prove(
  ``!w v:word32. w !! v = n2w (BITWISE 32 (\x y. x \/ y) (w2n w) (w2n v))``,
  REPEAT Cases THEN FULL_SIMP_TAC (srw_ss()) [word_or_n2w]
  THEN `(λx y. x ∨ y) = $\/` by FULL_SIMP_TAC std_ss [FUN_EQ_THM]
  THEN FULL_SIMP_TAC std_ss []);

val word_or_lemma16 = prove(
  ``!w v:word16. w !! v = n2w (BITWISE 16 (\x y. x \/ y) (w2n w) (w2n v))``,
  REPEAT Cases THEN FULL_SIMP_TAC (srw_ss()) [word_or_n2w]
  THEN `(λx y. x ∨ y) = $\/` by FULL_SIMP_TAC std_ss [FUN_EQ_THM]
  THEN FULL_SIMP_TAC std_ss []);

val res = translate word_or_lemma
val res = translate word_or_lemma16

val word_and_lemma = prove(
  ``!w v:word32. w && v = n2w (BITWISE 32 (\x y. x ∧ y) (w2n w) (w2n v))``,
  REPEAT Cases THEN FULL_SIMP_TAC (srw_ss()) [word_and_n2w]
  THEN `(λx y. x ∧ y) = (/\)` by FULL_SIMP_TAC std_ss [FUN_EQ_THM]
  THEN FULL_SIMP_TAC std_ss []);

val res = translate word_and_lemma

val res = translate (WORD_MUL_LSL |> INST_TYPE [alpha|->``:32``])
val res = translate (WORD_MUL_LSL |> INST_TYPE [alpha|->``:16``])
val res = translate (WORD_MUL_LSL |> INST_TYPE [alpha|->``:8``])

val WORD_LSR_LEMMA = prove(
  ``!w n. w >>> n = n2w (w2n w DIV 2**n)``,
  Cases THEN SIMP_TAC std_ss [GSYM w2n_11,w2n_lsr,w2n_n2w,n2w_w2n]
  THEN REPEAT STRIP_TAC
  THEN `n MOD dimword (:α) DIV 2 ** n' < dimword (:α)` by ALL_TAC
  THEN FULL_SIMP_TAC std_ss [DIV_LT_X]
  THEN Cases_on `(2:num) ** n'`
  THEN FULL_SIMP_TAC std_ss [ADD1] THEN DECIDE_TAC);

val res = translate (WORD_LSR_LEMMA |> INST_TYPE [alpha|->``:32``])
val res = translate (WORD_LSR_LEMMA |> INST_TYPE [alpha|->``:16``])
val res = translate (WORD_LSR_LEMMA |> INST_TYPE [alpha|->``:8``])

val word_msb_thm = prove(
  ``!w. word_msb (w:'a word) = BIT (dimindex (:'a) - 1) (w2n w)``,
  Cases THEN FULL_SIMP_TAC std_ss [word_msb_n2w,w2n_n2w]);

val word_lsb_thm = prove(
  ``!w. word_lsb (w:'a word) = ~(w2n w MOD 2 = 0)``,
  Cases THEN FULL_SIMP_TAC std_ss [word_lsb_n2w,w2n_n2w,ODD_EVEN,EVEN_MOD2]);

val sub_lemma = SIMP_RULE std_ss [word_2comp_def] word_sub_def

fun f32 lemma =
  lemma |> INST_TYPE [alpha|->``:32``] |> SIMP_RULE (srw_ss()) []

fun f16 lemma =
  lemma |> INST_TYPE [alpha|->``:16``] |> SIMP_RULE (srw_ss()) []

fun f8 lemma =
  lemma |> INST_TYPE [alpha|->``:8``] |> SIMP_RULE (srw_ss()) []

fun ff32 lemma =
  lemma |> INST_TYPE [alpha|->``:32``] |> SIMP_RULE (std_ss++SIZES_ss) []

fun ff16 lemma =
  lemma |> INST_TYPE [alpha|->``:16``] |> SIMP_RULE (std_ss++SIZES_ss) []

fun ff8 lemma =
  lemma |> INST_TYPE [alpha|->``:8``] |> SIMP_RULE (std_ss++SIZES_ss) []

val res = translate MIN_DEF
val res = translate (f32 word_msb_thm);
val res = translate (f16 word_msb_thm);
val res = translate (f8 word_msb_thm);
val res = translate (f32 word_lsb_thm);
val res = translate (f16 word_lsb_thm);
val res = translate (f8 word_lsb_thm);
val res = translate (f32 word_asr_n2w);
val res = translate (f16 word_asr_n2w);
val res = translate (ff32 sub_lemma);
val res = translate (ff16 sub_lemma);
val res = translate (ff8 sub_lemma);

val lemma = Q.prove (
`(h--l) (w:word32 ) = n2w (BITS (MIN h 31) l (w2n w))`,
`(h--l)w = (h--l)(n2w (w2n w))` by METIS_TAC [n2w_w2n] THEN
SRW_TAC [] [word_bits_n2w, dimindex_32]);

val res = translate lemma;
val res = translate (ff32 wordsTheory.word_ror)
val res = translate (ff32 wordsTheory.word_rol_def)

(* RC6 *)

val res = translate (find_def ``HD``)
val res = translate (find_def ``TL``)
val res = translate (find_def ``FST``)
val res = translate (find_def ``SND``)
val res = translate RC6Theory.GETKEYS_def
val res = translate RC6Theory.PreWhitening_def
(* ROTKEYS switches around a 44-tuple, so the next line takes a bit *)
val res = translate RC6Theory.ROTKEYS_def
val res = translate RC6Theory.InvPostWhitening_def
val res = translate RC6Theory.InvPreWhitening_def
val res = translate combinTheory.o_DEF
val res = translate RC6Theory.RightShift_def
val res = translate RC6Theory.LeftShift_def
val res = translate RC6Theory.CompUT_def
val res = translate RC6Theory.FwdRound_def
val res = translate RC6Theory.BwdRound_def
val res = translate RC6Theory.PostWhitening_def
val res = translate RC6Theory.Round_def
val res = translate RC6Theory.InvRound_def
val res = translate RC6Theory.r_def
val res = translate RC6_FWD_def
val res = translate RC6_BWD_def

val _ = export_theory ();