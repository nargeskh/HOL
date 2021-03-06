open HolKernel boolLib bossLib
open lcsymtacs set_sepTheory progTheory temporalTheory stateTheory

val _ = new_theory "temporal_state"

infix \\
val op \\ = op THEN;

(* ------------------------------------------------------------------------ *)

val TEMPORAL_NEXT_def = Define`
   TEMPORAL_NEXT model p c q =
   TEMPORAL model c (T_IMPLIES (NOW p) (NEXT (NOW q)))`

(* ------------------------------------------------------------------------ *)

val INIT = strip_tac
           \\ `?to_set next instr less. x = (to_set,next,instr,less)`
           by metis_tac [pairTheory.PAIR]

val TEMPORAL_NEXT_MOVE_COND = Q.store_thm("TEMPORAL_NEXT_MOVE_COND",
   `!x p c q g.
       TEMPORAL_NEXT x (p * cond g) c q <=> g ==> TEMPORAL_NEXT x p c q`,
   INIT
   \\ Cases_on `g`
   \\ simp [SEP_F_def, TEMPORAL_NEXT_def, TEMPORAL_def, SEP_CLAUSES,
            SEP_REFINE_def, T_IMPLIES_def, NOW_def]
   )

val TEMPORAL_NEXT_FRAME = Q.store_thm("TEMPORAL_NEXT_FRAME",
   `!x p c q. TEMPORAL_NEXT x p c q ==> !r. TEMPORAL_NEXT x (p * r) c (q * r)`,
   INIT
   \\ simp [GSYM STAR_ASSOC, TEMPORAL_NEXT_def, TEMPORAL_def,
            T_IMPLIES_def, NOW_def, NEXT_def]
   \\ REPEAT strip_tac
   \\ qpat_assum `!a. b`
         (qspecl_then [`state`, `seq`, `r * r'`] imp_res_tac)
   \\ fs [AC STAR_COMM STAR_ASSOC]
   )

val TEMPORAL_NEXT_DUPLICATE_COND = Q.store_thm("TEMPORAL_NEXT_DUPLICATE_COND",
   `!x p c q g.
        TEMPORAL_NEXT x (p * cond g) c q ==>
        TEMPORAL_NEXT x (p * cond g) c (q * cond g)`,
   simp [TEMPORAL_NEXT_MOVE_COND, SEP_CLAUSES]
   )

val TEMPORAL_NEXT_FALSE_PRE = Q.store_thm("TEMPORAL_NEXT_FALSE_PRE",
   `!x c q. TEMPORAL_NEXT x SEP_F c q`,
   INIT
   \\ simp [SEP_F_def, TEMPORAL_NEXT_def, TEMPORAL_def, SEP_CLAUSES,
            SEP_REFINE_def, T_IMPLIES_def, NOW_def]
   )

(* ------------------------------------------------------------------------ *)

val CODE_POOL_EMP = Q.prove(
   `!instr. CODE_POOL instr {} = emp`,
   simp [CODE_POOL_def, emp_def]
   )

val SPLIT_STATE_cor = METIS_PROVE [SPLIT_STATE]
   ``p (SELECT_STATE m y s) ==>
     ?u v. SPLIT (STATE m s) (u, v) /\ p u /\ (\v. v = FRAME_STATE m y s) v``

val TEMPORAL_STATE_SEMANTICS = Q.store_thm("TEMPORAL_STATE_SEMANTICS",
   `!m next instr p q.
       TEMPORAL_NEXT (STATE m, next, instr, (=)) p {} q =
       !state y seq.
          p (SELECT_STATE m y (seq 0)) /\ rel_sequence next seq state ==>
          q (SELECT_STATE m y (seq 1)) /\
          (FRAME_STATE m y (seq 0) = FRAME_STATE m y (seq 1))`,
   simp [TEMPORAL_NEXT_def, TEMPORAL_def, T_IMPLIES_def, NOW_def, NEXT_def,
         CODE_POOL_EMP, SEP_CLAUSES]
   \\ simp [STAR_def, SEP_REFINE_def]
   \\ REPEAT strip_tac
   \\ Tactical.REVERSE eq_tac
   \\ REPEAT strip_tac
   >- (full_simp_tac std_ss [SPLIT_STATE]
       \\ metis_tac [])
   \\ imp_res_tac SPLIT_STATE_cor
   \\ res_tac
   \\ full_simp_tac bool_ss [SPLIT_STATE]
   \\ metis_tac [FRAME_SET_EQ]
   )

val IMP_TEMPORAL = Q.prove(
   `!m next instr p q.
       (!y s.
          p (SELECT_STATE m y s) ==>
          ?v. (next s = SOME v) /\ q (SELECT_STATE m y v) /\
              (FRAME_STATE m y s = FRAME_STATE m y v)) ==>
       TEMPORAL_NEXT (STATE m, NEXT_REL (=) next, instr, (=)) p {} q`,
   rewrite_tac [TEMPORAL_STATE_SEMANTICS]
   \\ REPEAT strip_tac
   \\ `NEXT_REL (=) next (seq 0) (seq (SUC 0))`
   by (
       `?x. NEXT_REL (=) next (seq 0) x`
       by (res_tac
           \\ qexists_tac `v`
           \\ asm_simp_tac std_ss [NEXT_REL_def]
           \\ qexists_tac `seq 0`
           \\ asm_simp_tac std_ss []
           \\ full_simp_tac bool_ss [rel_sequence_def]
          )
       \\ metis_tac [rel_sequence_def]
      )
   \\ full_simp_tac std_ss [NEXT_REL_def]
   \\ qpat_assum `!y:'b set. P` (qspecl_then [`y`,`seq 0`] imp_res_tac)
   \\ metis_tac [optionTheory.SOME_11]
   )

val TEMPORAL_NEXT_CODE = Q.store_thm("TEMPORAL_NEXT_CODE",
   `!x p c q.
       TEMPORAL_NEXT x (CODE_POOL (FST (SND (SND x))) c * p) {}
                       (CODE_POOL (FST (SND (SND x))) c * q) =
    TEMPORAL_NEXT x p c q`,
   INIT
   \\ simp [TEMPORAL_NEXT_def, TEMPORAL_def, T_IMPLIES_def, NOW_def, NEXT_def,
            CODE_POOL_EMP, SEP_CLAUSES,
            AC set_sepTheory.STAR_ASSOC set_sepTheory.STAR_COMM]
   )

val TEMPORAL_MOVE_CODE = Q.store_thm("TEMPORAL_MOVE_CODE",
   `!to_set next instr less p c q.
       TEMPORAL_NEXT (to_set,next,instr,less)
          (p * CODE_POOL instr c) {} (q * CODE_POOL instr c) =
    TEMPORAL_NEXT (to_set,next,instr,less) p c q`,
   simp [TEMPORAL_NEXT_def, TEMPORAL_def, T_IMPLIES_def, NOW_def, NEXT_def,
         CODE_POOL_EMP, SEP_CLAUSES]
   )

val IMP_TEMPORAL = Theory.save_thm ("IMP_TEMPORAL",
   IMP_TEMPORAL
   |> Q.SPECL [`m`, `next`, `instr: 'd -> 'b # 'c -> bool`,
               `p * CODE_POOL instr (c: 'd -> bool)`,
               `q * CODE_POOL instr (c: 'd -> bool)`]
   |> REWRITE_RULE [TEMPORAL_MOVE_CODE]
   |> Q.GENL [`q`, `p`, `c`, `instr`, `next`, `m`]
   )

(* ------------------------------------------------------------------------ *)

val () = export_theory ()
