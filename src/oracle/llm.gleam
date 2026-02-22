/// LLM client — calls an OpenAI-compatible chat-completion endpoint.
///
/// Configure via environment variables:
///   LLM_BASE_URL   – e.g. https://api.openai.com/v1  (default: OpenAI)
///   LLM_API_KEY    – API key
///   LLM_MODEL      – model name, e.g. gpt-4o-mini (default: gpt-4o-mini)

import envoy
import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/json
import gleam/result
import gleam/string

pub type LlmError {
  HttpError(String)
  ParseError(String)
  ApiError(Int, String)
}

fn get_env(key: String, default: String) -> String {
  envoy.get(key) |> result.unwrap(default)
}

fn base_url() -> String {
  get_env("LLM_BASE_URL", "https://api.openai.com/v1")
}

fn api_key() -> String {
  get_env("LLM_API_KEY", "")
}

fn model() -> String {
  get_env("LLM_MODEL", "gpt-4o-mini")
}

/// Call the LLM with a prompt and return the text content of the first choice.
pub fn complete(prompt: String) -> Result(String, LlmError) {
  let body =
    json.object([
      #("model", json.string(model())),
      #(
        "messages",
        json.array(
          [
            json.object([
              #("role", json.string("user")),
              #("content", json.string(prompt)),
            ]),
          ],
          fn(x) { x },
        ),
      ),
      #("max_tokens", json.int(512)),
      #("temperature", json.float(0.0)),
    ])
    |> json.to_string

  let url = base_url() <> "/chat/completions"

  use base_req <- result.try(
    request.to(url)
    |> result.map_error(fn(_) { HttpError("Invalid LLM URL: " <> url) }),
  )

  let req =
    base_req
    |> request.set_method(http.Post)
    |> request.set_header("content-type", "application/json")
    |> request.set_header("authorization", "Bearer " <> api_key())
    |> request.set_body(body)

  use resp <- result.try(
    httpc.send(req)
    |> result.map_error(fn(e) { HttpError(string.inspect(e)) }),
  )

  case resp.status {
    200 -> extract_content(resp.body)
    status ->
      Error(ApiError(
        status,
        string.slice(resp.body, 0, 200),
      ))
  }
}

fn extract_content(body: String) -> Result(String, LlmError) {
  // Decode: { choices: [ { message: { content: "..." } } ] }
  let content_decoder =
    decode.at(
      ["choices", "0", "message", "content"],
      decode.string,
    )

  json.parse(body, content_decoder)
  |> result.map_error(fn(e) { ParseError(string.inspect(e)) })
}

/// Fetch the text content of a URL, then hand it to the LLM.
/// The prompt template may contain {content} which will be replaced
/// with the first 4000 characters of the fetched page.
pub fn run_with_url(
  source_url: String,
  prompt_template: String,
) -> Result(String, LlmError) {
  // Fetch the URL content
  let fetched = fetch_url(source_url)
  let content = case fetched {
    Ok(text) -> string.slice(text, 0, 4000)
    Error(_) -> "[Could not fetch " <> source_url <> "]"
  }
  let prompt = string.replace(prompt_template, each: "{content}", with: content)
  complete(prompt)
}

fn fetch_url(url: String) -> Result(String, String) {
  use base_req <- result.try(
    request.to(url)
    |> result.map_error(fn(_) { "Invalid URL: " <> url }),
  )
  let req =
    base_req
    |> request.set_header(
      "user-agent",
      "OracleBot/1.0 (BCH prediction market oracle)",
    )
  httpc.send(req)
  |> result.map(fn(r) { r.body })
  |> result.map_error(string.inspect)
}
