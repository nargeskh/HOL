signature Drop = 
sig
  include Abbrev

  val is_num_literal_hook      : (term -> bool) ref
  val is_int_literal_hook      : (term -> bool) ref
  val is_string_literal_hook   : (term -> bool) ref
  val is_list_hook             : (term -> bool) ref
  val is_comma_hook            : (term -> bool) ref
  val is_pair_hook             : (term -> bool) ref
  val is_let_hook              : (term -> bool) ref
  val is_pabs_hook             : (term -> bool) ref
  val is_one_hook              : (term -> bool) ref

  val dest_int_literal_hook    : (term -> Arbint.int) ref
  val dest_string_literal_hook : (term -> string) ref
  val dest_list_hook           : (term -> term list) ref
  val dest_cons_hook           : (term -> term * term) ref
  val dest_pair_hook           : (term -> term * term) ref
  val dest_pabs_hook           : (term -> term * term) ref
  val strip_let_hook           : (term -> (term * term) list list * term) ref

  val pp_type_as_ML     : ppstream -> hol_type -> unit
  val pp_term_as_ML     : string -> ppstream -> term -> unit
  val pp_defn_as_ML     : string -> ppstream -> term -> unit
  val pp_datatype_as_ML : ppstream -> string list * ParseDatatype.AST list -> unit

  datatype elem = DEFN of Thm.thm
                | DATATYPE of ParseDatatype.AST list
                | ABSDATATYPE of string list * ParseDatatype.AST list
                | MLSIG of string
                | MLSTRUCT of string

  val exportML : string * elem list -> unit
end
