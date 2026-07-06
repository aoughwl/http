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
