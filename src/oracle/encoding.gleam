/// JSON encoding helpers for the oracle domain types.

import gleam/json
import oracle/types.{type OracleResult, type OracleTask}

pub fn encode_task(task: OracleTask) -> json.Json {
  json.object([
    #("id", json.int(task.id)),
    #("name", json.string(task.name)),
    #("source_url", json.string(task.source_url)),
    #("prompt", json.string(task.prompt)),
    #("parse_rule", json.string(types.parse_rule_to_string(task.parse_rule))),
    #("interval_seconds", json.int(task.interval_seconds)),
    #("active", json.bool(task.active)),
    #("created_at", json.string(task.created_at)),
  ])
}

pub fn encode_result(r: OracleResult) -> json.Json {
  json.object([
    #("id", json.int(r.id)),
    #("task_id", json.int(r.task_id)),
    #("raw_response", json.string(r.raw_response)),
    #("parsed_value", json.string(r.parsed_value)),
    #("success", json.bool(r.success)),
    #("error", json.string(r.error)),
    #("executed_at", json.string(r.executed_at)),
  ])
}

pub fn encode_tasks(tasks: List(OracleTask)) -> String {
  json.array(tasks, encode_task) |> json.to_string
}

pub fn encode_results(results: List(OracleResult)) -> String {
  json.array(results, encode_result) |> json.to_string
}

pub fn encode_single_task(task: OracleTask) -> String {
  encode_task(task) |> json.to_string
}

pub fn encode_single_result(r: OracleResult) -> String {
  encode_result(r) |> json.to_string
}

pub fn ok_json(msg: String) -> String {
  json.object([#("ok", json.bool(True)), #("message", json.string(msg))])
  |> json.to_string
}

pub fn error_json(msg: String) -> String {
  json.object([#("ok", json.bool(False)), #("error", json.string(msg))])
  |> json.to_string
}
