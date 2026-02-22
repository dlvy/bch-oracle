/// Database layer using sqlight (SQLite).

import gleam/dynamic/decode
import gleam/int
import gleam/result
import oracle/types.{
  type OracleResult, type OracleTask, OracleResult, OracleTask,
}
import sqlight

pub type Db =
  sqlight.Connection

/// Open (or create) the SQLite database and run migrations.
pub fn connect(path: String) -> Result(Db, sqlight.Error) {
  use conn <- result.try(sqlight.open(path))
  use _ <- result.try(migrate(conn))
  Ok(conn)
}

fn migrate(conn: Db) -> Result(Nil, sqlight.Error) {
  sqlight.exec(
    "PRAGMA journal_mode=WAL;
     CREATE TABLE IF NOT EXISTS tasks (
       id              INTEGER PRIMARY KEY AUTOINCREMENT,
       name            TEXT    NOT NULL,
       source_url      TEXT    NOT NULL,
       prompt          TEXT    NOT NULL,
       parse_rule      TEXT    NOT NULL DEFAULT 'raw',
       interval_seconds INTEGER NOT NULL DEFAULT 3600,
       active          INTEGER NOT NULL DEFAULT 1,
       created_at      TEXT    NOT NULL DEFAULT (datetime('now'))
     );
     CREATE TABLE IF NOT EXISTS results (
       id           INTEGER PRIMARY KEY AUTOINCREMENT,
       task_id      INTEGER NOT NULL REFERENCES tasks(id),
       raw_response TEXT    NOT NULL DEFAULT '',
       parsed_value TEXT    NOT NULL DEFAULT '',
       success      INTEGER NOT NULL DEFAULT 0,
       error        TEXT    NOT NULL DEFAULT '',
       executed_at  TEXT    NOT NULL DEFAULT (datetime('now'))
     );
     CREATE INDEX IF NOT EXISTS idx_results_task_id ON results(task_id);
    ",
    conn,
  )
}

// ---------------------------------------------------------------------------
// Task CRUD
// ---------------------------------------------------------------------------

fn task_decoder() -> decode.Decoder(OracleTask) {
  use id <- decode.field(0, decode.int)
  use name <- decode.field(1, decode.string)
  use source_url <- decode.field(2, decode.string)
  use prompt <- decode.field(3, decode.string)
  use parse_rule_str <- decode.field(4, decode.string)
  use interval_seconds <- decode.field(5, decode.int)
  use active_int <- decode.field(6, decode.int)
  use created_at <- decode.field(7, decode.string)
  let parse_rule =
    types.parse_rule_from_string(parse_rule_str)
    |> result.unwrap(types.Raw)
  decode.success(OracleTask(
    id:,
    name:,
    source_url:,
    prompt:,
    parse_rule:,
    interval_seconds:,
    active: active_int == 1,
    created_at:,
  ))
}

pub fn create_task(
  conn: Db,
  name: String,
  source_url: String,
  prompt: String,
  parse_rule: types.ParseRule,
  interval_seconds: Int,
) -> Result(OracleTask, sqlight.Error) {
  let rule_str = types.parse_rule_to_string(parse_rule)
  use rows <- result.try(sqlight.query(
    "INSERT INTO tasks (name, source_url, prompt, parse_rule, interval_seconds)
     VALUES (?, ?, ?, ?, ?)
     RETURNING id, name, source_url, prompt, parse_rule, interval_seconds, active, created_at",
    conn,
    [
      sqlight.text(name),
      sqlight.text(source_url),
      sqlight.text(prompt),
      sqlight.text(rule_str),
      sqlight.int(interval_seconds),
    ],
    task_decoder(),
  ))
  case rows {
    [task, ..] -> Ok(task)
    [] -> Error(sqlight.SqlightError(sqlight.GenericError, "No row returned", 0))
  }
}

pub fn list_tasks(conn: Db) -> Result(List(OracleTask), sqlight.Error) {
  sqlight.query(
    "SELECT id, name, source_url, prompt, parse_rule, interval_seconds, active, created_at
     FROM tasks ORDER BY id",
    conn,
    [],
    task_decoder(),
  )
}

pub fn get_task(conn: Db, id: Int) -> Result(OracleTask, sqlight.Error) {
  use rows <- result.try(sqlight.query(
    "SELECT id, name, source_url, prompt, parse_rule, interval_seconds, active, created_at
     FROM tasks WHERE id = ?",
    conn,
    [sqlight.int(id)],
    task_decoder(),
  ))
  case rows {
    [task, ..] -> Ok(task)
    [] ->
      Error(sqlight.SqlightError(
        sqlight.GenericError,
        "Task not found: " <> int.to_string(id),
        0,
      ))
  }
}

pub fn list_active_tasks(conn: Db) -> Result(List(OracleTask), sqlight.Error) {
  sqlight.query(
    "SELECT id, name, source_url, prompt, parse_rule, interval_seconds, active, created_at
     FROM tasks WHERE active = 1 ORDER BY id",
    conn,
    [],
    task_decoder(),
  )
}

pub fn set_task_active(
  conn: Db,
  id: Int,
  active: Bool,
) -> Result(Nil, sqlight.Error) {
  let v = case active { True -> 1  False -> 0 }
  sqlight.exec(
    "UPDATE tasks SET active = " <> int.to_string(v) <> " WHERE id = " <> int.to_string(id),
    conn,
  )
}

pub fn delete_task(conn: Db, id: Int) -> Result(Nil, sqlight.Error) {
  sqlight.exec(
    "DELETE FROM tasks WHERE id = " <> int.to_string(id),
    conn,
  )
}

// ---------------------------------------------------------------------------
// Result CRUD
// ---------------------------------------------------------------------------

fn result_decoder() -> decode.Decoder(OracleResult) {
  use id <- decode.field(0, decode.int)
  use task_id <- decode.field(1, decode.int)
  use raw_response <- decode.field(2, decode.string)
  use parsed_value <- decode.field(3, decode.string)
  use success_int <- decode.field(4, decode.int)
  use error <- decode.field(5, decode.string)
  use executed_at <- decode.field(6, decode.string)
  decode.success(OracleResult(
    id:,
    task_id:,
    raw_response:,
    parsed_value:,
    success: success_int == 1,
    error:,
    executed_at:,
  ))
}

pub fn save_result(
  conn: Db,
  task_id: Int,
  raw_response: String,
  parsed_value: String,
  success: Bool,
  error: String,
) -> Result(OracleResult, sqlight.Error) {
  let s = case success { True -> 1  False -> 0 }
  use rows <- result.try(sqlight.query(
    "INSERT INTO results (task_id, raw_response, parsed_value, success, error)
     VALUES (?, ?, ?, ?, ?)
     RETURNING id, task_id, raw_response, parsed_value, success, error, executed_at",
    conn,
    [
      sqlight.int(task_id),
      sqlight.text(raw_response),
      sqlight.text(parsed_value),
      sqlight.int(s),
      sqlight.text(error),
    ],
    result_decoder(),
  ))
  case rows {
    [r, ..] -> Ok(r)
    [] -> Error(sqlight.SqlightError(sqlight.GenericError, "No row returned", 0))
  }
}

pub fn list_results(
  conn: Db,
  task_id: Int,
  limit: Int,
) -> Result(List(OracleResult), sqlight.Error) {
  sqlight.query(
    "SELECT id, task_id, raw_response, parsed_value, success, error, executed_at
     FROM results WHERE task_id = ?
     ORDER BY id DESC LIMIT ?",
    conn,
    [sqlight.int(task_id), sqlight.int(limit)],
    result_decoder(),
  )
}

pub fn latest_result(
  conn: Db,
  task_id: Int,
) -> Result(OracleResult, sqlight.Error) {
  use rows <- result.try(sqlight.query(
    "SELECT id, task_id, raw_response, parsed_value, success, error, executed_at
     FROM results WHERE task_id = ? ORDER BY id DESC LIMIT 1",
    conn,
    [sqlight.int(task_id)],
    result_decoder(),
  ))
  case rows {
    [r, ..] -> Ok(r)
    [] ->
      Error(sqlight.SqlightError(sqlight.GenericError, "No result found", 0))
  }
}

pub fn all_latest_results(conn: Db) -> Result(List(OracleResult), sqlight.Error) {
  sqlight.query(
    "SELECT r.id, r.task_id, r.raw_response, r.parsed_value, r.success, r.error, r.executed_at
     FROM results r
     INNER JOIN (
       SELECT task_id, MAX(id) as max_id FROM results GROUP BY task_id
     ) latest ON r.id = latest.max_id
     ORDER BY r.task_id",
    conn,
    [],
    result_decoder(),
  )
}

/// All results across all tasks (for the /results endpoint).
pub fn list_all_results(
  conn: Db,
  limit: Int,
) -> Result(List(OracleResult), sqlight.Error) {
  sqlight.query(
    "SELECT id, task_id, raw_response, parsed_value, success, error, executed_at
     FROM results ORDER BY id DESC LIMIT ?",
    conn,
    [sqlight.int(limit)],
    result_decoder(),
  )
}
