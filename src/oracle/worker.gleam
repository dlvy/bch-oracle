/// Worker — executes a single oracle task: fetch → LLM → parse → store.
///
/// Each task gets its own OTP actor (process) running a loop:
///   run → sleep(interval) → run → …

import envoy
import gleam/erlang/process
import gleam/io
import gleam/result
import gleam/string
import oracle/bch
import oracle/db
import oracle/ffi
import oracle/llm
import oracle/parser
import oracle/types.{type OracleTask}
import sqlight

/// Run one oracle task and persist the result.
pub fn run_task(conn: sqlight.Connection, task: OracleTask) -> Nil {
  io.println(
    "[worker] Running task #"
    <> string.inspect(task.id)
    <> " \""
    <> task.name
    <> "\"",
  )

  let outcome = execute(conn, task)
  case outcome {
    Ok(_) ->
      io.println(
        "[worker] Task #"
        <> string.inspect(task.id)
        <> " completed successfully",
      )
    Error(e) ->
      io.println(
        "[worker] Task #" <> string.inspect(task.id) <> " failed: " <> e,
      )
  }
}

fn execute(
  conn: sqlight.Connection,
  task: OracleTask,
) -> Result(Nil, String) {
  // 1. Call LLM (with fetched URL content if provided)
  let llm_result = case task.source_url {
    "" -> llm.complete(task.prompt)
    url -> llm.run_with_url(url, task.prompt)
  }

  case llm_result {
    Error(e) -> {
      let err_str = string.inspect(e)
      let _ = db.save_result(conn, task.id, "", "", False, err_str)
      Error(err_str)
    }
    Ok(raw) -> {
      // 2. Parse the response
      let parse_outcome = parser.parse(raw, task.parse_rule)
      let #(parsed, success, err_msg) = case parse_outcome {
        Ok(v) -> #(v, True, "")
        Error(msg) -> #("", False, msg)
      }

      // 3. Persist to database
      case db.save_result(conn, task.id, raw, parsed, success, err_msg) {
        Error(e) -> {
          io.println("[worker] Failed to save result: " <> string.inspect(e))
          Error("Database error: " <> string.inspect(e))
        }
        Ok(result) -> {
          // 4. Publish on-chain if enabled and successful
          let publish_enabled =
            envoy.get("BCH_PUBLISH_ENABLED")
            |> result.unwrap("false")
          
          case publish_enabled == "true" && success {
            False -> Nil
            True -> {
              case bch.publish_result(result) {
                Ok(pub_success) -> {
                  io.println(
                    "[worker] Published on-chain: "
                    <> pub_success.txid
                    <> " - "
                    <> pub_success.explorer_url,
                  )
                }
                Error(e) -> {
                  io.println(
                    "[worker] On-chain publish failed: " <> string.inspect(e),
                  )
                }
              }
            }
          }

          case success {
            True -> Ok(Nil)
            False -> Error(err_msg)
          }
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Per-task scheduler loop
// ---------------------------------------------------------------------------

/// Spawn a background OTP task that loops, running the oracle task on
/// its configured interval. The task is re-read from the DB on each
/// iteration so changes (interval, active flag) take effect without restart.
pub fn spawn_task_loop(conn: sqlight.Connection, task_id: Int) -> Nil {
  ffi.spawn(fn() { task_loop(conn, task_id) })
}

fn task_loop(conn: sqlight.Connection, task_id: Int) -> Nil {
  case db.get_task(conn, task_id) {
    Error(_) -> {
      io.println(
        "[scheduler] Task #"
        <> string.inspect(task_id)
        <> " not found, stopping loop",
      )
      Nil
    }
    Ok(task) -> {
      case task.active {
        False -> {
          // Task disabled — check again in 30 s
          process.sleep(30_000)
          task_loop(conn, task_id)
        }
        True -> {
          run_task(conn, task)
          process.sleep(task.interval_seconds * 1000)
          task_loop(conn, task_id)
        }
      }
    }
  }
}
