open Biocaml_internal_pervasives
open Result
module Pos = Biocaml_pos

type item = string

let lstrip = String.lstrip
let rstrip = String.rstrip
let strip = String.strip

module Error = struct

  type t = [
  | `premature_end_of_input
  ]

end

let string_to_items s =
  match String.split ~on:'\n' s with
  | [] -> assert false
  | [""] -> [], false
  | lines ->
    let n = List.length lines in
    match List.nth lines (n - 1) with
    | None -> assert false
    | Some "" -> List.take lines (n - 1), true
    | Some _ -> lines, false

module Buffer = struct

  type t = {
    mutable unfinished_line : string option;
    lines : item Queue.t;
    mutable parsed_lines : int;
    filename : string option;
  }

  let make ?filename () =
    {unfinished_line = None;
     lines = Queue.create ();
     parsed_lines = 0;
     filename}

  let feed_line p s =
    Queue.enqueue p.lines s

  let feed_string p s =
    let lines = String.split s ~on:'\n' in
    let rec faux = function
      | [] -> assert false
      | [ "" ] -> (* last char was a "\n" *) ()
      | [ s ] -> (* there is a partial line at the end *)
        p.unfinished_line <- Some s;
      | h :: t ->
        Queue.enqueue p.lines h;
        faux t
    in
    match p.unfinished_line, lines with
    | _, [] -> assert false
    | _, [""] -> ()
    | None, l -> faux l
    | Some s, h :: t ->
      p.unfinished_line <- None;
      faux ((s ^ h) :: t)

  let queued_lines p = Queue.length p.lines

  let next_line p =
    let l = Queue.dequeue p.lines in
    if l <> None then (
      p.parsed_lines <- p.parsed_lines + 1;
    );
    l

  exception No_next_line

  let next_line_exn p =
    match next_line p with
    | Some s -> s
    | None -> raise No_next_line

  let current_position p =
    Pos.make ?file:p.filename ~line:p.parsed_lines ()

  let is_empty p =
    Queue.is_empty p.lines && p.unfinished_line = None

  let contents p = Queue.to_list p.lines, p.unfinished_line

  let empty p = (Queue.clear p.lines; p.unfinished_line <- None)

end

module Transform = struct

  let string_to_item () =
    let buf = Buffer.make () in
    Biocaml_transform.make ~name:"lines"
      ~feed:(Buffer.feed_string buf)
      ~next:(function
        | true -> (match Buffer.next_line buf with
            | Some line -> `output line
            | None -> (match Buffer.contents buf with
                | [], None -> `end_of_stream
                | [], Some unfinished_line ->
                    (Buffer.empty buf; `output unfinished_line)
                | _ -> assert false
              )
          )
        | false -> (match Buffer.next_line buf with
            | None -> `not_ready
            | Some line -> `output line
          )
      )
      ()

  let group2 () =
    let queue : (item * item) Queue.t= Queue.create () in
    let item1 = ref None in
    Biocaml_transform.make ~name:"group2"
      ~feed:(function item -> match !item1 with
        | Some item1' -> (
            Queue.enqueue queue (item1', item);
            item1 := None
          )
        | None -> item1 := Some item
      )
      ~next:(fun stopped -> match Queue.dequeue queue with
        | Some ij -> output_ok ij
        | None ->
          if not stopped then
            `not_ready
          else
            (match !item1 with
             | None -> `end_of_stream
             | Some _ -> output_error `premature_end_of_input
            )
      )
      ()

  let make ?name ?filename ~next ~on_error () =
    let lo_parser = Buffer.make ?filename () in
    Biocaml_transform.make ?name ()
      ~feed:(Buffer.feed_string lo_parser)
      ~next:(fun stopped ->
        match next lo_parser with
        | `output (Ok r) -> `output (Ok r)
        | `output (Error r) -> `output (Error (on_error (`next r)))
        | `not_ready ->
          if stopped then (
            if Buffer.is_empty lo_parser then
              `end_of_stream
            else
              let l,o = Buffer.contents lo_parser in
              `output
                (Error
                    (on_error
                        (`incomplete_input (Buffer.current_position lo_parser, l, o))))
          ) else
            `not_ready)

  let make_merge_error =
    make
      ~on_error:(function
        | `next e -> e
        | `incomplete_input e -> `incomplete_input e)

end

let of_char_stream cstr =
  let module Buffer = Biocaml_internal_pervasives.Buffer in
  let f _ = match Stream.peek cstr with
    | None -> None
    | Some _ ->
      let ans = Buffer.create 100 in
      let rec loop () =
        try
          let c = Stream.next_exn cstr in
          if c <> '\n' then (Buffer.add_char ans c; loop())
        with Core.Std.Caml.Stream.Failure -> ()
      in 
      loop();
      Some (Buffer.contents ans)
  in
  Stream.from f

let of_channel cin =
  let f _ =
    try Some (input_line cin)
    with End_of_file -> None
  in Stream.from f

let to_channel xs oc =
  Stream.iter xs ~f:(fun l ->
    output_string oc l ; output_char oc '\n'
  )
