/// Bitcoin Cash on-chain integration.
/// Publishes oracle results to BCH blockchain via CashScript contracts.

import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/json
import gleam/result
import gleam/string
import oracle/types.{type OracleResult}
import shellout

pub type PublishError {
  NodeScriptError(String)
  ParseError(String)
  ContractNotDeployed(Int)
}

pub type PublishSuccess {
  PublishSuccess(txid: String, explorer_url: String)
}

/// Publish an oracle result on-chain.
/// Calls the Node.js bridge script to interact with CashScript.
pub fn publish_result(
  result: OracleResult,
) -> Result(PublishSuccess, PublishError) {
  // Only publish successful results
  case result.success {
    False -> Error(NodeScriptError("Cannot publish failed result"))
    True -> {
      let timestamp = unix_timestamp_now()
      let task_id_str = int.to_string(result.task_id)
      let timestamp_str = int.to_string(timestamp)
      
      io.println(
        "[bch] Publishing result for task #"
        <> task_id_str
        <> " to blockchain: "
        <> result.parsed_value,
      )
      
      // Call Node.js publish script
      let script_path = "./contracts/publish.js"
      let args = [task_id_str, timestamp_str, result.parsed_value]
      
      case shellout.command(run: "node", with: [script_path, ..args], in: ".", opt: []) {
        Error(#(exit_code, stderr)) -> {
          io.println("[bch] Publish failed: " <> stderr)
          Error(NodeScriptError(
            "Exit code "
            <> int.to_string(exit_code)
            <> ": "
            <> stderr,
          ))
        }
        Ok(stdout) -> {
          // Parse JSON response from Node.js script
          parse_publish_response(stdout)
        }
      }
    }
  }
}

fn parse_publish_response(
  json_str: String,
) -> Result(PublishSuccess, PublishError) {
  let success_decoder = decode.at(["success"], decode.bool)
  let txid_decoder = decode.at(["txid"], decode.string)
  let url_decoder = decode.at(["explorerUrl"], decode.string)
  let error_decoder = decode.at(["error"], decode.string)
  
  case json.parse(json_str, success_decoder) {
    Error(_) -> Error(ParseError("Invalid JSON response: " <> json_str))
    Ok(False) -> {
      let err_msg =
        json.parse(json_str, error_decoder)
        |> result.unwrap("Unknown error")
      Error(NodeScriptError(err_msg))
    }
    Ok(True) -> {
      use txid <- result.try(
        json.parse(json_str, txid_decoder)
        |> result.map_error(fn(_) { ParseError("Missing txid in response") }),
      )
      use url <- result.try(
        json.parse(json_str, url_decoder)
        |> result.map_error(fn(_) {
          ParseError("Missing explorerUrl in response")
        }),
      )
      Ok(PublishSuccess(txid:, explorer_url: url))
    }
  }
}

/// Deploy a contract for a specific task.
/// Returns the contract address.
pub fn deploy_contract(task_id: Int) -> Result(String, PublishError) {
  io.println("[bch] Deploying contract for task #" <> int.to_string(task_id))
  
  let script_path = "./contracts/deploy.js"
  let args = [int.to_string(task_id)]
  
  case shellout.command(run: "node", with: [script_path, ..args], in: ".", opt: []) {
    Error(#(exit_code, stderr)) ->
      Error(NodeScriptError(
        "Deploy failed (exit "
        <> int.to_string(exit_code)
        <> "): "
        <> stderr,
      ))
    Ok(stdout) -> {
      // Extract contract address from output
      case string.split(stdout, "Address: ") {
        [_, rest] -> {
          case string.split(rest, "\n") {
            [address, ..] -> {
              io.println("[bch] Contract deployed at: " <> address)
              Ok(string.trim(address))
            }
            [] -> Error(ParseError("Could not parse contract address"))
          }
        }
        _ -> Error(ParseError("Could not find contract address in output"))
      }
    }
  }
}

/// Get current Unix timestamp in seconds.
fn unix_timestamp_now() -> Int {
  // Use Erlang's system time
  let microseconds = erlang_system_time_microseconds()
  microseconds / 1_000_000
}

@external(erlang, "erlang", "system_time")
fn erlang_system_time_microseconds() -> Int
