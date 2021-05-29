open Mldoc
open Mldoc.Parser
open Angstrom
open! Prelude

let ast_to_json ast = Type.blocks_to_yojson ast |> Yojson.Safe.to_string

let generate backend ?refs config doc output =
  let export = Exporters.find backend in
  Exporters.run export ~refs config doc output

let _ =
  let open Js_of_ocaml in
  Js.export "Mldoc"
    (object%js
       method parseJson input config_json =
         let config_json = Js.to_string config_json in
         let config_json = Yojson.Safe.from_string config_json in
         match Conf.of_yojson config_json with
         | Ok config -> (
           try
             let str = Js.to_string input in
             parse config str |> ast_to_json |> Js.string
           with error ->
             print_endline (Printexc.to_string error);
             input)
         | Error e -> Js_of_ocaml.Js.string ("Config error: " ^ e)

       method parseInlineJson input config_json =
         let config_json = Js.to_string config_json in
         let config_json = Yojson.Safe.from_string config_json in
         match Conf.of_yojson config_json with
         | Ok config -> (
           let str = Js.to_string input in
           match parse_string ~consume:All (Mldoc.Inline.parse config) str with
           | Ok result ->
             Mldoc.Type.inline_list_to_yojson result
             |> Yojson.Safe.to_string |> Js.string
           | Error e ->
             print_endline e;
             input)
         | Error e -> Js_of_ocaml.Js.string ("Config error: " ^ e)

       method parseHtml input config_json =
         let str = Js.to_string input in
         let config_json = Js.to_string config_json in
         let buffer = Buffer.create 1024 in
         let config_json = Yojson.Safe.from_string config_json in
         match Conf.of_yojson config_json with
         | Ok config ->
           let ast = parse config str in
           let document = Document.from_ast None ast in
           let _ =
             Sys_js.set_channel_flusher stdout (fun s ->
                 Buffer.add_string buffer s)
           in
           generate "html" config document stdout;
           flush stdout;
           Js_of_ocaml.Js.string (Buffer.contents buffer)
         | Error error -> Js_of_ocaml.Js.string error

       method parseAndExportMarkdown input config_json references =
         let str = Js.to_string input in
         let config_json = Js.to_string config_json in
         let references_json =
           Js.to_string references |> Yojson.Safe.from_string
         in
         let buffer = Buffer.create 1024 in
         let config_json = Yojson.Safe.from_string config_json in
         match
           (Conf.of_yojson config_json, Reference.of_yojson references_json)
         with
         | Ok config, Ok references ->
           let ast = parse config str in
           let parsed_embed_blocks =
             CCList.map
               (fun (k, (content_include_children, content)) ->
                 ( k
                 , ( fst @@ unzip @@ parse config content_include_children
                   , fst @@ unzip @@ parse config content ) ))
               references.embed_blocks
           in
           let parsed_embed_pages =
             CCList.map
               (fun (k, v) -> (k, fst @@ unzip @@ parse config v))
               references.embed_pages
           in
           let refs : Reference.parsed_t =
             { parsed_embed_blocks; parsed_embed_pages }
           in
           let document = Document.from_ast None ast in
           let _ =
             Sys_js.set_channel_flusher stdout (fun s ->
                 Buffer.add_string buffer s)
           in
           generate "markdown" ~refs config document stdout;
           flush stdout;
           Js_of_ocaml.Js.string (Buffer.contents buffer)
         | Error error, _ -> Js_of_ocaml.Js.string error
         | _, Error error -> Js_of_ocaml.Js.string error

       method astExportOPML ast =
         let ast = Js.to_string ast |> Yojson.Safe.from_string in
         let buffer = Buffer.create 1024 in
         match Type.blocks_of_yojson ast with
         | Ok ast ->
           let document = Document.from_ast None ast in
           let _ =
             Sys_js.set_channel_flusher stdout (fun s ->
                 Buffer.add_string buffer s)
           in
           let dummy_config : Conf.t =
             { toc = true
             ; heading_number = true
             ; keep_line_break = false
             ; format = Conf.Markdown
             ; heading_to_list = true
             ; exporting_keep_properties = false
             ; ignore_heading_list_marker = true
             }
           in
           generate "opml" dummy_config document stdout;
           flush stdout;
           Js.string (Buffer.contents buffer)
         | Error error -> Js.string ("json->ast err: " ^ error)

       method astExportMarkdown ast config_json references =
         let ast = Js.to_string ast |> Yojson.Safe.from_string in
         let config_json =
           Js.to_string config_json |> Yojson.Safe.from_string
         in
         let references_json =
           Js.to_string references |> Yojson.Safe.from_string
         in
         let buffer = Buffer.create 1024 in
         match
           ( Conf.of_yojson config_json
           , Reference.of_yojson references_json
           , Type.blocks_of_yojson ast )
         with
         | Ok config, Ok references, Ok ast ->
           let parsed_embed_blocks =
             CCList.map
               (fun (k, (content_include_children, content)) ->
                 ( k
                 , ( fst @@ unzip @@ parse config content_include_children
                   , fst @@ unzip @@ parse config content ) ))
               references.embed_blocks
           in
           let parsed_embed_pages =
             CCList.map
               (fun (k, v) -> (k, fst @@ unzip @@ parse config v))
               references.embed_pages
           in
           let refs : Reference.parsed_t =
             { parsed_embed_blocks; parsed_embed_pages }
           in
           let document = Document.from_ast None ast in
           let _ =
             Sys_js.set_channel_flusher stdout (fun s ->
                 Buffer.add_string buffer s)
           in
           generate "markdown" ~refs config document stdout;
           flush stdout;
           Js_of_ocaml.Js.string (Buffer.contents buffer)
         | Error error, _, _ ->
           Js_of_ocaml.Js.string ("json->config err: " ^ error)
         | _, Error error, _ ->
           Js_of_ocaml.Js.string ("json->references err: " ^ error)
         | _, _, Error error -> Js_of_ocaml.Js.string ("json->ast err: " ^ error)

       method anchorLink s =
         let s = Js.to_string s in
         Js_of_ocaml.Js.string (Heading.anchor_link s)

       method timestampToString input =
         let str = Js.to_string input in
         let json = Yojson.Safe.from_string str in
         match Timestamp.of_yojson json with
         | Ok t -> Timestamp.to_string t |> Js.string
         | Error error -> Js_of_ocaml.Js.string error

       method rangeToString input =
         let str = Js.to_string input in
         let json = Yojson.Safe.from_string str in
         match Range.of_yojson json with
         | Ok t -> Range.to_string t |> Js.string
         | Error error -> Js_of_ocaml.Js.string error
    end)
