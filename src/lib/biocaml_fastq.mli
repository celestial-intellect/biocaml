(** FASTQ data. *)


(** {2 The Item Type } *)

type item = {
  name: string;
  sequence: string;
  comment: string;
  qualities: string;
}
(** Type of FASTQ items. *)

(** {2 The Error Types } *)

module Error : sig
  (** All errors generated by any function in the [Fastq] module
      are defined here.

    - [`sequence_and_qualities_do_not_match (position, sequence,
    qualities)] - given [sequence] and [qualities] at given [position]
    are of different lengths.

    - [`wrong_name_line x] - name line [x] does not start with '@'

    - [`wrong_comment_line _] - comment line does not start with '+'

    - [`incomplete_input (position, lines, s)] - the input ended
    prematurely. Trailing contents, which cannot be used to fully
    construct an item, are provided: [lines] is any complete lines
    parsed and [s] is any final string not ending in a newline.
  *)

  type fasta_pair_to_fastq =
    [ `cannot_convert_to_phred_score of int list
    | `sequence_names_mismatch of string * string ]
  (** The errors of the {!Transform.fasta_pair_to_fastq}. *)

  type parsing =
      [ `sequence_and_qualities_do_not_match of Biocaml_pos.t * string * string
      | `wrong_comment_line of Biocaml_pos.t * string
      | `wrong_name_line of Biocaml_pos.t * string
      | `incomplete_input of Biocaml_pos.t * string list * string option
      ]
  (** The parsing errors. *)

  type t = [ parsing | fasta_pair_to_fastq ]
  (** Union of all possible errors. *)

  val t_of_sexp : Sexplib.Sexp.t -> t
  val sexp_of_t : t -> Sexplib.Sexp.t

  val t_to_string : t -> string
  (** Transform error to a human-readable string. *)

end

exception Parse_error of Biocaml_pos.t * string
(** Indicates a parse error at the given [pos]. The string is a
    message explaining the error. *)

module Parse : sig
  (** Parsing functions. Mostly needed only internally. Each function
  takes:

      - [line] - The line to parse.

      - [pos] - Optional position of the line used in error
      reporting. The column should always be 1 because by definition a
      line starts at the beginning.

  All raise [Parse_error].
  *)

  val name : ?pos:Biocaml_pos.t -> Biocaml_line.t -> string
  val sequence : ?pos:Biocaml_pos.t -> Biocaml_line.t -> string
  val comment : ?pos:Biocaml_pos.t -> Biocaml_line.t -> string

  (** [qualities sequence line] parses given qualities [line] in the
      context of a previously parsed [sequence]. The [sequence] is needed
      to assure the correct number of quality scores are provided. If not
      provided, this check is omitted. *)
  val qualities :
    ?pos:Biocaml_pos.t ->
    ?sequence:string ->
    Biocaml_line.t ->
    string

end

(** {2 [In_channel] Functions } *)

exception Error of Error.t
(** The only exception raised by this module. *)

val in_channel_to_item_stream : ?buffer_size:int -> ?filename:string -> in_channel ->
  (item, [> Error.parsing]) Core.Result.t Stream.t
(** Parse an input-channel into a stream of [item] results. *)

val in_channel_to_item_stream_exn:
  ?buffer_size:int -> ?filename:string -> in_channel -> item Stream.t
(** Returns a stream of [item]s.
    [Stream.next] will raise [Error _] in case of any error. *)


(** {2 [To_string] Function }

    This function converts [item] values to strings that can be
    dumped to a file, i.e. they contain full-lines, including {i all}
    end-of-line characters.
*)

val item_to_string: item -> string
(** Convert a [item] to a string. *)


(** {2 Transforms } *)

module Transform: sig
  (** Lower-level transforms. *)

  val string_to_item:
    ?filename:string -> unit ->
    (string, (item, [> Error.parsing]) Core.Result.t) Biocaml_transform.t
  (** Create a [Biocaml_transform.t] from arbitrary strings to
      [item] values.*)

  val item_to_string: unit -> (item, string) Biocaml_transform.t
  (** Create a [Biocaml_transform.t] from [item] values to strings. *)

  val trim:
    [ `beginning of int | `ending of int ] ->
    (item, (item, [> `invalid_size of int]) Core.Result.t) Biocaml_transform.t
  (** Create a [Biocaml_transform.t] that trims FASTQ items. *)

  val fasta_pair_to_fastq:
    ?phred_score_offset:[ `offset33 | `offset64 ] ->
    unit ->
    (Biocaml_fasta.char_seq Biocaml_fasta.item *
       Biocaml_fasta.int_seq Biocaml_fasta.item,
     (item,
      [> Error.fasta_pair_to_fastq ]) Core.Result.t)
      Biocaml_transform.t
  (** Create a transform that builds [item] records thanks
      to sequences from [Fasta.(char_seq item)] values
      and qualities converted from
      [Fasta.(int_seq item)] values. The default Phred score encoding
      is [`offset33] (like in {!Biocaml_phred_score}). *)

  val fastq_to_fasta_pair :
    ?phred_score_offset:[ `offset33 | `offset64 ] ->
    unit ->
    (item,
     (Biocaml_fasta.char_seq Biocaml_fasta.item *
        Biocaml_fasta.int_seq Biocaml_fasta.item,
      [> `cannot_convert_ascii_phred_score of string ]) Core.Result.t)
      Biocaml_transform.t
  (** Create a transform that split a FASTQ item into to FASTA items
      (i.e. the inverse of {!fasta_pair_to_fastq}). *)

end


(** {2 S-Expressions } *)

val item_of_sexp : Sexplib.Sexp.t -> item
val sexp_of_item : item -> Sexplib.Sexp.t
