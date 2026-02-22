/// Web API router built with Wisp.
///
/// Endpoints:
///   GET    /tasks                    – list all tasks
///   POST   /tasks                    – create a task
///   GET    /tasks/:id                – get task by id
///   DELETE /tasks/:id                – delete task
///   PUT    /tasks/:id/activate       – enable task
///   PUT    /tasks/:id/deactivate     – disable task
///   POST   /tasks/:id/run            – run task immediately (async)
///   GET    /tasks/:id/results        – recent results for task (default 20)
///   GET    /results                  – all recent results (default 50)
///   GET    /health                   – health check

import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/json
import gleam/result
import gleam/string
import oracle/bch
import oracle/db
import oracle/encoding
import oracle/ffi
import oracle/types
import oracle/worker
import sqlight
import wisp.{type Request, type Response}

pub type Context {
  Context(db: sqlight.Connection)
}

pub fn handle_request(req: Request, ctx: Context) -> Response {
  case wisp.path_segments(req) {
    // Health check
    ["health"] -> health()

    // Tasks collection
    ["tasks"] ->
      case req.method {
        wisp.Get -> list_tasks(ctx)
        wisp.Post -> create_task(req, ctx)
        _ -> wisp.method_not_allowed([wisp.Get, wisp.Post])
      }

    // Single task
    ["tasks", id_str] ->
      case int.parse(id_str) {
        Error(_) -> bad_request("Invalid task id: " <> id_str)
        Ok(id) ->
          case req.method {
            wisp.Get -> get_task(id, ctx)
            wisp.Delete -> delete_task(id, ctx)
            _ -> wisp.method_not_allowed([wisp.Get, wisp.Delete])
          }
      }

    // Task actions
    ["tasks", id_str, "activate"] ->
      case int.parse(id_str) {
        Error(_) -> bad_request("Invalid task id")
        Ok(id) -> set_active(id, True, ctx)
      }

    ["tasks", id_str, "deactivate"] ->
      case int.parse(id_str) {
        Error(_) -> bad_request("Invalid task id")
        Ok(id) -> set_active(id, False, ctx)
      }

    ["tasks", id_str, "run"] ->
      case int.parse(id_str) {
        Error(_) -> bad_request("Invalid task id")
        Ok(id) ->
          case req.method {
            wisp.Post -> run_task_now(id, ctx)
            _ -> wisp.method_not_allowed([wisp.Post])
          }
      }

    // Results for a task
    ["tasks", id_str, "results"] ->
      case int.parse(id_str) {
        Error(_) -> bad_request("Invalid task id")
        Ok(id) -> list_task_results(id, 20, ctx)
      }

    // Deploy contract for a task
    ["tasks", id_str, "deploy-contract"] ->
      case int.parse(id_str) {
        Error(_) -> bad_request("Invalid task id")
        Ok(id) ->
          case req.method {
            wisp.Post -> deploy_contract(id, ctx)
            _ -> wisp.method_not_allowed([wisp.Post])
          }
      }

    // All results
    ["results"] -> list_all_results(50, ctx)

    // 404
    _ -> wisp.not_found()
  }
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

fn health() -> Response {
  json_ok(encoding.ok_json("Oracle service is running"))
}

fn list_tasks(ctx: Context) -> Response {
  case db.list_tasks(ctx.db) {
    Ok(tasks) -> json_ok(encoding.encode_tasks(tasks))
    Error(e) -> json_error(500, string.inspect(e))
  }
}

fn get_task(id: Int, ctx: Context) -> Response {
  case db.get_task(ctx.db, id) {
    Ok(task) -> json_ok(encoding.encode_single_task(task))
    Error(_) -> json_error(404, "Task not found: " <> int.to_string(id))
  }
}

/// POST /tasks body (JSON):
/// {
///   "name": "BCH Price above $400?",
///   "source_url": "https://coinmarketcap.com/currencies/bitcoin-cash/",
///   "prompt": "Based on this page: {content}\n\nIs the current BCH price above $400? Answer YES or NO.",
///   "parse_rule": "yes_no",       // "yes_no" | "numeric" | "price" | "raw"
///   "interval_seconds": 3600
/// }
fn create_task(req: Request, ctx: Context) -> Response {
  use body <- wisp.require_json(req)

  let name_dec = decode.at(["name"], decode.string)
  let url_dec = decode.at(["source_url"], decode.string)
  let prompt_dec = decode.at(["prompt"], decode.string)
  let rule_dec = decode.at(["parse_rule"], decode.string)
  let interval_dec = decode.at(["interval_seconds"], decode.int)

  let parsed = {
    use name <- result.try(
      decode.run(body, name_dec)
      |> result.map_error(fn(_) { "Missing field: name" }),
    )
    use source_url <- result.try(
      decode.run(body, url_dec)
      |> result.map_error(fn(_) { "Missing field: source_url" }),
    )
    use prompt <- result.try(
      decode.run(body, prompt_dec)
      |> result.map_error(fn(_) { "Missing field: prompt" }),
    )
    let rule_str =
      decode.run(body, rule_dec)
      |> result.unwrap("raw")
    use parse_rule <- result.try(
      types.parse_rule_from_string(rule_str)
      |> result.map_error(fn(e) { e }),
    )
    let interval =
      decode.run(body, interval_dec)
      |> result.unwrap(3600)
    Ok(#(name, source_url, prompt, parse_rule, interval))
  }

  case parsed {
    Error(msg) -> bad_request(msg)
    Ok(#(name, source_url, prompt, parse_rule, interval)) -> {
      case db.create_task(ctx.db, name, source_url, prompt, parse_rule, interval) {
        Error(e) -> json_error(500, string.inspect(e))
        Ok(task) -> {
          // Start the background loop for this new task
          let _ = worker.spawn_task_loop(ctx.db, task.id)
          wisp.response(201)
          |> wisp.set_header("content-type", "application/json")
          |> wisp.string_body(encoding.encode_single_task(task))
        }
      }
    }
  }
}

fn delete_task(id: Int, ctx: Context) -> Response {
  case db.delete_task(ctx.db, id) {
    Ok(_) ->
      json_ok(encoding.ok_json("Task " <> int.to_string(id) <> " deleted"))
    Error(e) -> json_error(500, string.inspect(e))
  }
}

fn set_active(id: Int, active: Bool, ctx: Context) -> Response {
  case db.set_task_active(ctx.db, id, active) {
    Ok(_) -> {
      let state = case active {
        True -> "activated"
        False -> "deactivated"
      }
      json_ok(encoding.ok_json("Task " <> int.to_string(id) <> " " <> state))
    }
    Error(e) -> json_error(500, string.inspect(e))
  }
}

fn run_task_now(id: Int, ctx: Context) -> Response {
  case db.get_task(ctx.db, id) {
    Error(_) -> json_error(404, "Task not found: " <> int.to_string(id))
    Ok(task) -> {
      // Run in a fresh process so the HTTP response is immediate
      ffi.spawn(fn() { worker.run_task(ctx.db, task) })
      json_ok(
        encoding.ok_json(
          "Task " <> int.to_string(id) <> " triggered asynchronously",
        ),
      )
    }
  }
}

fn list_task_results(id: Int, limit: Int, ctx: Context) -> Response {
  case db.list_results(ctx.db, id, limit) {
    Ok(results) -> json_ok(encoding.encode_results(results))
    Error(e) -> json_error(500, string.inspect(e))
  }
}

fn list_all_results(limit: Int, ctx: Context) -> Response {
  case db.list_all_results(ctx.db, limit) {
    Ok(results) -> json_ok(encoding.encode_results(results))
    Error(e) -> json_error(500, string.inspect(e))
  }
}

fn deploy_contract(id: Int, ctx: Context) -> Response {
  // Verify task exists
  case db.get_task(ctx.db, id) {
    Error(_) -> json_error(404, "Task not found: " <> int.to_string(id))
    Ok(_task) -> {
      // Deploy contract asynchronously
      ffi.spawn(fn() {
        case bch.deploy_contract(id) {
          Ok(address) -> {
            io.println(
              "[router] Contract deployed for task #"
              <> int.to_string(id)
              <> " at "
              <> address,
            )
          }
          Error(e) -> {
            io.println(
              "[router] Contract deployment failed for task #"
              <> int.to_string(id)
              <> ": "
              <> string.inspect(e),
            )
          }
        }
      })
      json_ok(
        encoding.ok_json(
          "Contract deployment initiated for task " <> int.to_string(id),
        ),
      )
    }
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn json_ok(body: String) -> Response {
  wisp.ok()
  |> wisp.set_header("content-type", "application/json")
  |> wisp.string_body(body)
}

fn json_error(status: Int, msg: String) -> Response {
  wisp.response(status)
  |> wisp.set_header("content-type", "application/json")
  |> wisp.string_body(encoding.error_json(msg))
}

fn bad_request(msg: String) -> Response {
  wisp.response(400)
  |> wisp.set_header("content-type", "application/json")
  |> wisp.string_body(encoding.error_json(msg))
}
