## parseResponse — the client-side mirror of parseRequest.
##
## The interesting cases are the ones a real wire produces: a header block that
## has not fully arrived, a status line with no reason phrase, a chunked body
## (which the parser must hand back UNdecoded, since framing is the caller's
## decision), and rubbish (which must report, not raise).

import std/syncio
import http/response
import http/headers

var failures = 0

proc check(cond: bool; what: string) =
  if not cond:
    echo "FAIL: ", what
    inc failures

block simple:
  let r = parseResponse("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n" &
                        "Content-Length: 5\r\n\r\nhello")
  check(r.status == 200, "status 200")
  check(r.contentType == "text/plain", "content type picked up")
  check(r.body == "hello", "body")
  check(headerValue(r, "content-length") == "5", "header lookup is case-insensitive")
  check(hasHeader(r, "Content-Type"), "hasHeader")

block noReasonPhrase:
  let r = parseResponse("HTTP/1.1 204\r\n\r\n")
  check(r.status == 204, "status with no reason phrase")
  check(r.body.len == 0, "empty body")

block bareLf:
  # Some servers still emit bare LF; the parser must not require CRLF.
  let r = parseResponse("HTTP/1.0 301 Moved Permanently\nLocation: /new\n\n")
  check(r.status == 301, "bare-LF status line")
  check(headerValue(r, "Location") == "/new", "bare-LF header")

block chunkedStaysChunked:
  let raw = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n" &
            "5\r\nhello\r\n0\r\n\r\n"
  let r = parseResponse(raw)
  check(r.status == 200, "chunked status")
  check(r.body.len > 5, "chunked body handed back undecoded")
  check(decodeChunked(r.body) == "hello", "and decodeChunked finishes the job")

block garbage:
  let r = parseResponse("not an http response at all\r\n\r\n")
  check(r.status == 0, "garbage reports status 0 rather than raising")

block headerEnd:
  check(responseHeaderEnd("HTTP/1.1 200 OK\r\nA: b\r\n") < 0,
        "incomplete header block is not yet complete")
  check(responseHeaderEnd("HTTP/1.1 200 OK\r\nA: b\r\n\r\nxx") == 25,
        "header end offset points just past the blank line")
  check(responseHeaderEnd("HTTP/1.1 200 OK\nA: b\n\nxx") == 22,
        "header end offset, bare LF")

block statusLineIncomplete:
  var v = ""
  var s = 0
  var reason = ""
  check(parseStatusLine("HTTP/1.1 200 O", v, s, reason) < 0,
        "a status line with no terminator is incomplete, not a 200")

if failures == 0:
  echo "tresponse_parse: all checks passed"
else:
  echo "tresponse_parse: ", failures, " failures"
  quit(1)
