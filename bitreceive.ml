open Printf
open Core.Std
open Bitcoin

type config_t = {
  rpcip: string; rpcport: int; rpcuser: string; rpcpassword: string; nconfirm: int; mutex_file:string; state_file: string;
  min_seconds_between_call: int; output_pipe: string; 
} with sexp

type state_t = { last_included_block: string option; has_work: bool; last_called : float } with sexp

module Connection_config =
struct
  let default = None
end

module CoinService = Bitcoin.Make (Bitcoin_ocamlnet.Httpclient) (Connection_config)

let mutex config =
  let mutex_file = config.mutex_file in
  let fd = Unix.openfile mutex_file ~mode:[Unix.O_WRONLY;Unix.O_CREAT] in
  let _ = Unix.lockf fd ~mode:Unix.F_LOCK ~len:(Int64.of_int 0) in
  fd

let get_state state_file =
  if (Sys.file_exists state_file) = `Yes then
    (state_t_of_sexp (Sexp.of_string (In_channel.read_all state_file)))
  else
    { last_included_block= None; has_work= true; last_called=0. }

let save_state state_file state = Out_channel.write_all state_file ~data:(Sexp.to_string (sexp_of_state_t state))

let scan_and_notify config state =
  let conn =
    {
      Bitcoin.inet_addr = Unix.Inet_addr.of_string config.rpcip;
      host = "localhost";
      port = config.rpcport;
      username = config.rpcuser;
      password = config.rpcpassword
    }
  in
  let (txs,_) =
    match state.last_included_block with
      None -> CoinService.listsinceblock ~conn ()
    | Some blockhash -> CoinService.listsinceblock ~conn ~blockhash ()
  in
  let (min_safe_block_info, has_work, txs) = List.fold_left ~init:(None,false,[]) ~f:(fun acc tx -> 
      (*Yojson.Safe.pretty_to_channel stdout (`Assoc tx);*)
      let (min_safe_block_info,has_work,tx_acc) = acc in
      match (List.Assoc.find tx "category") with
        Some (`String "receive") -> 
        begin match (List.Assoc.find tx "address", List.Assoc.find tx "amount", List.Assoc.find tx "confirmations") with
            (Some (`String address), Some (`Float amount), Some (`Int confirmations)) -> 
            let tx_acc = `Assoc [
              ("address", (`String address));
              ("amount", (`Intlit (Int64.to_string (Bitcoin.amount_of_float amount))));
              ("confirmations", (`Int confirmations))
            ] :: tx_acc in
            let min_safe_block_info =
              if confirmations >= config.nconfirm then
                begin match (List.Assoc.find tx "blockhash", min_safe_block_info) with
                    (Some (`String blockhash), None) -> Some (confirmations, blockhash)
                  | (Some (`String blockhash), Some (min_safe_block_nconfirm,min_safe_block)) -> 
                    if min_safe_block_nconfirm > confirmations then
                      Some (confirmations, blockhash)
                    else
                      min_safe_block_info
                  | _ -> assert false
                end
              else
                min_safe_block_info
            in
              (min_safe_block_info, (has_work || confirmations < config.nconfirm), tx_acc)
          | _ -> assert false
        end
      | _ -> acc
    ) txs
  in
  let last_included_block =
    match min_safe_block_info with
      None -> state.last_included_block
    | Some (_, blockhash) -> Some blockhash
  in

  let json_string = Yojson.Safe.to_string (`Assoc [("last_included_block", `String (match last_included_block with None -> "" | Some bl -> bl));("incoming",`List txs)]) in
  Out_channel.write_all config.output_pipe ~data:(sprintf "%s\n" json_string);
  save_state config.state_file {last_included_block = last_included_block; has_work = has_work; last_called = Unix.time ()}

let _ =
  match Sys.argv with
    [|_;"walletnotify";config_file;txid|] -> 
    let config = config_t_of_sexp (Sexp.of_string (In_channel.read_all config_file)) in
    let mud = mutex config in

    let state = get_state config.state_file in

    begin
    if (Unix.time() -. state.last_called > (Float.of_int config.min_seconds_between_call)) then
      scan_and_notify config state
    end;

    Unix.close mud
  | [|_;"blocknotify";config_file;blockid|] ->
    let config = config_t_of_sexp (Sexp.of_string (In_channel.read_all config_file)) in
    let mud = mutex config in

    let state = get_state config.state_file in
    begin
      if (Unix.time() -. state.last_called > (Float.of_int config.min_seconds_between_call) && state.has_work) then
        scan_and_notify config state
    end;

    Unix.close mud
  | _ -> raise (Invalid_argument "Usage: bitreceive <walletnotify|blocknotify> <config_file> %s")


