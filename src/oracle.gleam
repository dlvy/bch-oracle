/// Oracle service — BCH prediction market oracle.
///
/// Starts the HTTP API server and boots scheduler loops for all active tasks.
///
/// Configuration via environment variables:
///   PORT         – HTTP port (default: 8080)
///   DB_PATH      – SQLite file path (default: ./oracle.db)
///   LLM_BASE_URL – OpenAI-compatible base URL (default: https://api.openai.com/v1)
///   LLM_API_KEY  – API key
///   LLM_MODEL    – model name (default: gpt-4o-mini)

import envoy
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import mist
import oracle/db
import oracle/router
import oracle/worker
import wisp
import wisp/wisp_mist

pub fn main() {
  wisp.configure_logger()

  let port =
    envoy.get("PORT")
    |> result.try(int.parse)
    |> result.unwrap(8080)

  let db_path = envoy.get("DB_PATH") |> result.unwrap("./oracle.db")

  // Open database
  let conn = case db.connect(db_path) {
    Ok(c) -> {
      io.println("[oracle] Database opened: " <> db_path)
      c
    }
    Error(e) -> {
      io.println("[oracle] FATAL: Cannot open database: " <> string.inspect(e))
      panic as "database connection failed"
    }
  }

  // Boot scheduler loops for all currently active tasks
  case db.list_active_tasks(conn) {
    Ok(tasks) -> {
      let count = list.length(tasks)
      io.println(
        "[oracle] Booting "
        <> int.to_string(count)
        <> " active task scheduler(s)…",
      )
      list.each(tasks, fn(task) {
        let _ = worker.spawn_task_loop(conn, task.id)
        io.println(
          "[oracle]   → task #"
          <> int.to_string(task.id)
          <> " \""
          <> task.name
          <> "\" every "
          <> int.to_string(task.interval_seconds)
          <> "s",
        )
      })
    }
    Error(e) ->
      io.println(
        "[oracle] Warning: could not load active tasks: " <> string.inspect(e),
      )
  }

  // Build the Wisp request handler
  let ctx = router.Context(db: conn)
  let handler = fn(req) { router.handle_request(req, ctx) }
  
  let secret_key_base = wisp.random_string(64)

  // Start the HTTP server
  let assert Ok(_) =
    wisp_mist.handler(handler, secret_key_base)
    |> mist.new
    |> mist.port(port)
    |> mist.start

  io.println(
    "[oracle] HTTP API listening on http://localhost:"
    <> int.to_string(port),
  )

  process.sleep_forever()
}
