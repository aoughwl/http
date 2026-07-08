## thttp.aowl — smoke tests for the generic HTTP helper pack.

import http

proc startsWith(s, prefix: string): bool =
  if prefix.len > s.len: return false
  var i = 0
  while i < prefix.len:
    if s[i] != prefix[i]: return false
    inc i
  return true

proc contains(s, needle: string): bool =
  if needle.len == 0: return true
  if needle.len > s.len: return false
  var i = 0
  while i + needle.len <= s.len:
    var ok = true
    var j = 0
    while j < needle.len:
      if s[i + j] != needle[j]:
        ok = false
      inc j
    if ok: return true
    inc i
  return false

proc check(ok: bool; msg: string) =
  if not ok:
    discard msg
    let zero = 0
    discard 1 div zero

let raw = "POST /submit?q=nimony&empty= HTTP/1.1\r\n" &
          "Host: example.test\r\n" &
          "Content-Type: application/x-www-form-urlencoded\r\n" &
          "\r\n" &
          "name=aoughwl+http&encoded=x%2Fy"
let req = parseRequest(raw)

check(req.isValidRequest(), "request should parse")
check(req.isMethod("post"), "method lookup should be case-insensitive")
check(req.path == "/submit?q=nimony&empty=", "request target should be preserved")
check(req.version == "HTTP/1.1", "version should parse")
check(headerValue(req, "host") == "example.test", "header lookup should be case-insensitive")
check(queryParam(req.path, "q") == "nimony", "query param should decode")
check(queryParam(req.path, "empty") == "", "empty query param should be empty")
check(formParam(req.body, "name") == "aoughwl http", "form + should decode as space")
check(formParam(req.body, "encoded") == "x/y", "form percent escape should decode")
check(pathOnly(req.path) == "/submit", "pathOnly should strip query")
check(queryString(req.path) == "q=nimony&empty=", "queryString should strip leading ?")
check(percentDecode("hello%20world") == "hello world", "percentDecode should decode hex")
check(percentDecode("bad%zz") == "bad%zz", "bad escape should be copied")

let h = @[header("X-Test", "one"), header("Content-Type", "text/plain")]
check(headerValue(h, "x-test") == "one", "seq header lookup should work")
check(hasHeader(h, "CONTENT-TYPE"), "seq hasHeader should be case-insensitive")

var res = response(201, "text/plain", "created")
res.withHeader("X-Test", "yes")
let rendered = responseToString(res)
check(startsWith(rendered, "HTTP/1.1 201 Created"), "status line should render")
check(contains(rendered, "X-Test: yes"), "custom header should render")
check(contains(rendered, "Content-Length: 7"), "content length should render")
check(contains(rendered, "\r\n\r\ncreated"), "body should render")

let headOut = responseToString(res, false)
check(contains(headOut, "Content-Length: 7"), "HEAD-style response keeps content length")
check(not contains(headOut, "\r\n\r\ncreated"), "HEAD-style response suppresses body")

check(reasonPhrase(404) == "Not Found", "reason phrase should cover 404")
check(contains(redirect("/next"), "Location: /next"), "redirect should include Location")
check(contains(optionsResponse("GET, HEAD"), "Allow: GET, HEAD"), "options should include Allow")

# --- task 1: percentDecode bounds (escape at exact end of string) ---
check(percentDecode("a%2F") == "a/", "escape at very end should decode")
check(percentDecode("%2F") == "/", "single trailing escape should decode")
check(percentDecode("%2") == "%2", "truncated escape stays literal")
check(percentDecode("ab%20") == "ab ", "trailing %20 should decode")

# --- task 2: reasonPhrase fallback + added codes ---
check(reasonPhrase(599) == "", "unknown code should not claim OK")
check(reasonPhrase(200) == "OK", "200 still OK")
check(reasonPhrase(100) == "Continue", "100 added")
check(reasonPhrase(308) == "Permanent Redirect", "308 present")
check(reasonPhrase(451) == "Unavailable For Legal Reasons", "451 added")
check(reasonPhrase(504) == "Gateway Timeout", "504 added")
check(reasonPhrase(511) == "Network Authentication Required", "511 added")

# --- task 3: typed HttpMethod ---
check(parseHttpMethod("get") == HttpGet, "parse is case-insensitive")
check(parseHttpMethod("POST") == HttpPost, "parse POST")
check(parseHttpMethod("PATCH") == HttpPatch, "parse PATCH")
check(parseHttpMethod("frobnicate") == HttpUnknown, "unknown method")
check(toString(HttpDelete) == "DELETE", "toString round-trips")
check($HttpPut == "PUT", "$ renders method token")
check(parseHttpMethod(toString(HttpOptions)) == HttpOptions, "method round-trip")
check(req.isMethod(HttpPost), "typed isMethod matches parsed request")
check(not req.isMethod(HttpGet), "typed isMethod rejects wrong method")

# --- task 4: typed HttpCode ---
check($code(200) == "200 OK", "HttpCode renders reason")
check($code(404) == "404 Not Found", "HttpCode renders 404")
check($code(599) == "599", "unknown HttpCode is number only")
check(code(200).toInt == 200, "toInt returns underlying value")
check(is1xx(code(100)), "1xx class")
check(is2xx(code(204)), "2xx class")
check(is3xx(code(301)), "3xx class")
check(is4xx(code(404)), "4xx class")
check(is5xx(code(503)), "5xx class")
check(not is2xx(code(404)), "class helpers are exclusive")

# --- task 5: percentEncode / encodeQuery / queryParams ---
let tricky = "a b/c?d=e&f+g#h%z"
check(percentDecode(percentEncode(tricky)) == tricky, "encode/decode round-trip")
check(percentEncode("a b") == "a%20b", "space encodes to %20 by default")
check(percentEncode("a b", true) == "a+b", "space encodes to + when asked")
check(percentEncode("-._~") == "-._~", "unreserved chars pass through")
check(percentEncode("/") == "%2F", "reserved char encodes")
check(encodeQuery(@[("q", "a b"), ("x", "1/2")]) == "q=a+b&x=1%2F2", "encodeQuery builds pairs")

let qp = queryParams("a=1&a=2&b=&c")
check(qp.len == 4, "queryParams enumerates every pair")
check(qp[0][0] == "a" and qp[0][1] == "1", "first pair")
check(qp[1][0] == "a" and qp[1][1] == "2", "repeated key preserved")
check(qp[2][0] == "b" and qp[2][1] == "", "empty value")
check(qp[3][0] == "c" and qp[3][1] == "", "bare key")
let qp2 = queryParams("name=aoughwl+http")
check(qp2[0][1] == "aoughwl http", "queryParams decodes +")

# --- task 6: chunked transfer coding ---
check(decodeChunked(encodeChunked("hello world")) == "hello world", "chunked round-trip")
check(encodeChunked("") == "0\r\n\r\n", "empty body is just terminator")
check(decodeChunked("4\r\nWiki\r\n5\r\npedia\r\n0\r\n\r\n") == "Wikipedia", "multi-chunk decode")
check(decodeChunked(encodeChunked("")) == "", "empty chunked decodes empty")
