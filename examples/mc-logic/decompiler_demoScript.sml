
open HolKernel boolLib bossLib Parse;
open tailrecTheory tailrecLib decompilerLib;
open listTheory pred_setTheory arithmeticTheory wordsTheory;

val _ = new_theory "decompiler_demo";


(* ARM code for length of linked-list *)

val (arm_th,arm_defs) = decompile_arm "arm_length" `
  E3A00000  (*    mov r0,#0       *)
  E3510000  (* L: cmp r1,#0       *)
  12800001  (*    addne r0,r0,#1  *)
  15911000  (*    ldrne r1,[r1]   *)
  1AFFFFFB  (*    bne L           *)`;

(* formalising notion of linked-list *)

val llist_def = Define `
  (llist [] (a:word32,dm,m:word32->word32) = (a = 0w)) /\
  (llist (x::xs) (a,dm,m) = ~(a = 0w) /\ (a && 3w = 0w) /\ {a;a+4w} SUBSET dm /\
     ?a'. (m a = a') /\ (m (a+4w) = x) /\ llist xs (a',dm,m))`;

(* verification proof *)

val arm_length1_thm = prove(
  ``!ys a y dm m. llist ys (a,dm,m) ==> arm_length1_pre (y,a,dm,m) /\
                  (arm_length1 (y,a,dm,m) = (y + n2w (LENGTH ys),0w,dm,m))``,
  Induct THEN ONCE_REWRITE_TAC [arm_defs]
  THEN SIMP_TAC (bool_ss++tailrec_part_ss()) [llist_def,LENGTH,WORD_ADD_0,LET_DEF,EMPTY_SUBSET, 
    INSERT_SUBSET, ONCE_REWRITE_RULE [ADD_COMM] ADD1, GSYM word_add_n2w, WORD_ADD_ASSOC] 
  THEN METIS_TAC [])

val arm_length_thm = prove(
  ``!ys y dm m. llist ys (y,dm,m) ==> arm_length_pre (y,dm,m) /\
                (arm_length (y,dm,m) = (n2w (LENGTH ys),0w,dm,m))``,
  ONCE_REWRITE_TAC [arm_defs]
  THEN SIMP_TAC (std_ss++helperLib.pbeta_ss) [LET_DEF]
  THEN METIS_TAC [arm_length1_thm,WORD_ADD_0]);

(* combining the verification proof with the generated theorem *)

val th = save_thm("ARM_LIST_SPEC",INST_SPEC arm_th arm_length_thm);

(* implemented on PowerPC and IA-32 *)

val (ppc_th,ppc_defs) = decompile_ppc "ppc_length" `
  38A00000  (*     addi 5,0,0   *)
  2C140000  (* L1: cmpwi 20,0   *)
  40820010  (*     bc 4,2,L2    *)
  82940000  (*     lwz 20,0(20) *)
  38A50001  (*     addi 5,5,1   *)
  4BFFFFF0  (*     b L1         *)
            (* L2:              *)`;

val (ia32_th,ia32_defs) = decompile_ia32 "ia32_length" `
  31C0  (*     xor eax, eax       *)
  85F6  (* L1: test esi, esi      *)
  7405  (*     jz L2              *)
  40    (*     inc eax            *)
  8B36  (*     mov esi, [esi]     *)
  EBF7  (*     jmp L1             *)
        (* L2:                    *)`;

(* verification proof *)

val ppc_length_eq = prove(
  ``(arm_length = ppc_length) /\ (arm_length_pre = ppc_length_pre)``,
  TAILREC_EQ_TAC());

val ia32_length_eq = prove(
  ``(arm_length = ia32_length) /\ (arm_length_pre = ia32_length_pre)``,
  TAILREC_EQ_TAC());

val ppc_length_thm = REWRITE_RULE [ppc_length_eq] arm_length_thm;
val ia32_length_thm = REWRITE_RULE [ia32_length_eq] arm_length_thm;

(* combining the verification proof with the generated theorem *)

val th = save_thm("PPC_LIST_SPEC",INST_SPEC ppc_th ppc_length_thm);
val th = save_thm("IA32_LIST_SPEC",INST_SPEC ia32_th ia32_length_thm);


val _ = export_theory();
