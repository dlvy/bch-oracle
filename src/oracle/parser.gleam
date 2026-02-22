/// Response parsing strategies for LLM output.

import gleam/float
import gleam/regexp
import gleam/string
import oracle/types.{type ParseRule, Numeric, Price, Raw, YesNo}

/// Parse the raw LLM response string according to the given rule.
/// Returns Ok(parsed_string) or Error(reason).
pub fn parse(raw: String, rule: ParseRule) -> Result(String, String) {
  let trimmed = string.trim(raw)
  case rule {
    Raw -> Ok(trimmed)
    YesNo -> parse_yes_no(trimmed)
    Numeric -> parse_numeric(trimmed)
    Price -> parse_price(trimmed)
  }
}

fn parse_yes_no(s: String) -> Result(String, String) {
  let lower = string.lowercase(s)
  case
    string.contains(lower, "yes"),
    string.contains(lower, "no")
  {
    True, False -> Ok("yes")
    False, True -> Ok("no")
    True, True -> {
      // Both present — pick whichever appears first
      let yes_pos = find_pos(lower, "yes")
      let no_pos = find_pos(lower, "no")
      case yes_pos < no_pos {
        True -> Ok("yes")
        False -> Ok("no")
      }
    }
    False, False ->
      Error(
        "Could not find YES or NO in response: \""
        <> string.slice(s, 0, 60)
        <> "\"",
      )
  }
}

fn find_pos(haystack: String, needle: String) -> Int {
  case string.split_once(haystack, needle) {
    Ok(#(before, _)) -> string.length(before)
    Error(_) -> 99_999
  }
}

fn parse_numeric(s: String) -> Result(String, String) {
  // Try to extract the first number (integer or float) from the string
  let assert Ok(re) =
    regexp.from_string("[+-]?\\d[\\d,]*\\.?\\d*([eE][+-]?\\d+)?")
  case regexp.scan(re, s) {
    [match, ..] -> {
      let digits = string.replace(match.content, each: ",", with: "")
      Ok(digits)
    }
    [] ->
      Error(
        "No numeric value found in: \""
        <> string.slice(s, 0, 60)
        <> "\"",
      )
  }
}

fn parse_price(s: String) -> Result(String, String) {
  // Strip currency symbols ($, €, £, ¥, BCH, BTC …) then parse as numeric
  let cleaned =
    s
    |> string.replace(each: "$", with: "")
    |> string.replace(each: "€", with: "")
    |> string.replace(each: "£", with: "")
    |> string.replace(each: "¥", with: "")
    |> string.replace(each: "BCH", with: "")
    |> string.replace(each: "BTC", with: "")
    |> string.replace(each: "USD", with: "")
  case parse_numeric(cleaned) {
    Error(e) -> Error(e)
    Ok(num_str) ->
      // Normalise to a clean float string
      case float.parse(num_str) {
        Ok(f) -> Ok(float.to_string(f))
        Error(_) -> Ok(num_str)
      }
  }
}
