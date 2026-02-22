/// Core domain types for the BCH Oracle Prediction Market Service.

/// The parse strategy applied to the LLM response.
pub type ParseRule {
  /// Expect a "YES" or "NO" answer (case-insensitive).
  YesNo
  /// Extract a floating-point number from the response.
  Numeric
  /// Extract a price value (e.g. "$42,100.50" → 42100.50).
  Price
  /// Return the raw trimmed LLM response string.
  Raw
}

pub fn parse_rule_to_string(rule: ParseRule) -> String {
  case rule {
    YesNo -> "yes_no"
    Numeric -> "numeric"
    Price -> "price"
    Raw -> "raw"
  }
}

pub fn parse_rule_from_string(s: String) -> Result(ParseRule, String) {
  case s {
    "yes_no" -> Ok(YesNo)
    "numeric" -> Ok(Numeric)
    "price" -> Ok(Price)
    "raw" -> Ok(Raw)
    _ -> Error("Unknown parse rule: " <> s)
  }
}

/// A scheduled oracle task. The oracle periodically calls the LLM,
/// parses the response, and stores the result.
pub type OracleTask {
  OracleTask(
    id: Int,
    name: String,
    /// URL of the data source to include in the prompt (e.g. a crypto price page).
    source_url: String,
    /// The prompt template sent to the LLM. Use {content} as placeholder for fetched content.
    prompt: String,
    /// How to parse the LLM response into a usable value.
    parse_rule: ParseRule,
    /// Interval in seconds between task executions.
    interval_seconds: Int,
    /// Whether this task is active.
    active: Bool,
    created_at: String,
  )
}

/// One execution result of an oracle task.
pub type OracleResult {
  OracleResult(
    id: Int,
    task_id: Int,
    /// Raw LLM response.
    raw_response: String,
    /// Parsed value as a string (e.g. "yes", "42100.50", "NO").
    parsed_value: String,
    /// Whether parsing succeeded.
    success: Bool,
    executed_at: String,
    /// Optional error message if execution/parsing failed.
    error: String,
  )
}
