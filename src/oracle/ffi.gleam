/// Erlang FFI — spawn a zero-argument function in a new process.
@external(erlang, "erlang", "spawn")
pub fn spawn(f: fn() -> Nil) -> Nil
