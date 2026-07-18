## tstream.aowl — behavioral tests for the incremental HTTP parser.
##
## Feeds requests and responses through `StreamParser` byte-by-byte AND in
## pseudo-random chunk sizes, and asserts the parsed head/body exactly match
## parsing the same message whole with `parseRequest`. Covers Content-Length,
## chunked, a split in the middle of a chunk-size line, need-more-data
## reporting, and no-over-read on trailing (pipelined) bytes.

import http

proc check(ok: bool; msg: string) =
  if not ok:
    discard msg
    let zero = 0
    discard 1 div zero

proc sameHeaders(a, b: seq[Header]): bool =
  if a.len != b.len: return false
  var i = 0
  while i < a.len:
    if a[i].name != b[i].name: return false
    if a[i].value != b[i].value: return false
    inc i
  return true

# A tiny deterministic LCG so "random-ish" chunking is reproducible.
var rngState = 0x2545F491'u32
proc nextRnd(hi: int): int =
  rngState = rngState * 1103515245'u32 + 12345'u32
  let v = int((rngState shr 16) and 0x7fff'u32)
  if hi <= 1: 1 else: (v mod hi) + 1

# Drive a parser with fixed-size pieces; returns bytes consumed up to (and
# including) message completion. Asserts need-more before completion and that
# `feed` consumes exactly each piece until the message ends.
proc driveFixed(p: var StreamParser; msg: string; chunk: int): int =
  var pos = 0
  while pos < msg.len:
    var piece = ""
    var k = 0
    while k < chunk and pos + k < msg.len:
      piece.add msg[pos + k]
      inc k
    check(not p.isComplete, "should not be complete before feeding remaining bytes")
    check(p.needMore(), "partial feed must report need-more-data")
    let consumed = p.feed(piece)
    check(consumed == piece.len, "feed must consume the whole piece within a message")
    pos = pos + consumed
    if p.isComplete(): break
  return pos

# Drive with pseudo-random piece sizes.
proc driveRandom(p: var StreamParser; msg: string): int =
  var pos = 0
  while pos < msg.len:
    let want = nextRnd(7)
    var piece = ""
    var k = 0
    while k < want and pos + k < msg.len:
      piece.add msg[pos + k]
      inc k
    let consumed = p.feed(piece)
    check(consumed == piece.len, "random feed must consume the whole piece")
    pos = pos + consumed
    if p.isComplete(): break
  return pos

# ---------------------------------------------------------------------------
# 1. Content-Length request: whole vs byte-by-byte vs random chunks.
# ---------------------------------------------------------------------------
let reqCL = "POST /submit?q=nimony HTTP/1.1\r\n" &
            "Host: example.test\r\n" &
            "Content-Type: application/x-www-form-urlencoded\r\n" &
            "Content-Length: 11\r\n" &
            "\r\n" &
            "hello world"
let wholeCL = parseRequest(reqCL)
check(wholeCL.body == "hello world", "sanity: whole parse body")

block:
  var p = newRequestParser()
  let consumed = driveFixed(p, reqCL, 1)
  check(p.isComplete(), "byte-by-byte CL request completes")
  check(consumed == reqCL.len, "byte-by-byte consumes exactly the message")
  let r = p.toRequest()
  check(r.meth == wholeCL.meth, "meth matches whole parse")
  check(r.path == wholeCL.path, "path matches whole parse")
  check(r.version == wholeCL.version, "version matches whole parse")
  check(sameHeaders(r.headers, wholeCL.headers), "headers match whole parse")
  check(r.body == wholeCL.body, "body matches whole parse")
  check(p.bodyLength() == 11, "bodyLength counts decoded body")

block:
  var p = newRequestParser()
  let consumed = driveRandom(p, reqCL)
  check(p.isComplete(), "random-chunk CL request completes")
  check(consumed == reqCL.len, "random-chunk consumes exactly the message")
  let r = p.toRequest()
  check(r.meth == wholeCL.meth and r.path == wholeCL.path, "random head matches")
  check(sameHeaders(r.headers, wholeCL.headers), "random headers match")
  check(r.body == wholeCL.body, "random body matches")

# ---------------------------------------------------------------------------
# 2. Chunked request: byte-by-byte, decoded body must equal the payload.
# ---------------------------------------------------------------------------
let payload = "WikipediaThePedia"
let chunkedBody = "4\r\nWiki\r\n5\r\npedia\r\n8\r\nThePedia\r\n0\r\n\r\n"
let reqChunked = "POST /upload HTTP/1.1\r\n" &
                 "Host: example.test\r\n" &
                 "Transfer-Encoding: chunked\r\n" &
                 "\r\n" & chunkedBody
check(decodeChunked(chunkedBody) == payload, "sanity: whole decodeChunked")

block:
  var p = newRequestParser()
  let consumed = driveFixed(p, reqChunked, 1)
  check(p.isComplete(), "byte-by-byte chunked request completes")
  check(consumed == reqChunked.len, "chunked byte-by-byte consumes exactly")
  let r = p.toRequest()
  check(r.meth == "POST" and r.path == "/upload", "chunked head parsed")
  check(headerValue(r.headers, "transfer-encoding") == "chunked", "TE header preserved")
  check(r.body == payload, "incremental de-chunked body equals payload")

block:
  var p = newRequestParser()
  discard driveRandom(p, reqChunked)
  check(p.isComplete(), "random chunked request completes")
  check(p.toRequest().body == payload, "random de-chunked body equals payload")

# ---------------------------------------------------------------------------
# 3. Split in the MIDDLE of the chunk-size line.
#    Feed "...\r\nTransfer... \r\n\r\n1" then "a\r\n<26 bytes>..." so the "1a"
#    hex size (26) straddles two feeds.
# ---------------------------------------------------------------------------
block:
  let sizeStraddleBody = "1a\r\nabcdefghijklmnopqrstuvwxyz\r\n0\r\n\r\n"
  let head = "POST /x HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n"
  var p = newRequestParser()
  # First feed ends right after the first hex digit '1' of the size line.
  let part1 = head & "1"
  let c1 = p.feed(part1)
  check(c1 == part1.len, "first split feed consumed fully")
  check(p.needMore(), "mid-chunk-size split still needs more data")
  check(not p.isComplete(), "not complete mid-chunk-size")
  # Second feed supplies the rest, starting with the second hex digit 'a'.
  let part2 = "a\r\nabcdefghijklmnopqrstuvwxyz\r\n0\r\n\r\n"
  let c2 = p.feed(part2)
  check(c2 == part2.len, "second split feed consumed fully")
  check(p.isComplete(), "chunk-size-split message completes")
  check(p.toRequest().body == "abcdefghijklmnopqrstuvwxyz", "26-byte chunk decoded across the split")

# ---------------------------------------------------------------------------
# 4. Response: status line + Content-Length body, byte-by-byte + random.
# ---------------------------------------------------------------------------
let respMsg = "HTTP/1.1 404 Not Found\r\n" &
              "Content-Type: text/plain\r\n" &
              "Content-Length: 9\r\n" &
              "\r\n" &
              "not found"
block:
  var p = newResponseParser()
  let consumed = driveFixed(p, respMsg, 1)
  check(p.isComplete(), "byte-by-byte response completes")
  check(consumed == respMsg.len, "response byte-by-byte consumes exactly")
  let r = p.toResponse()
  check(r.status == 404, "status parsed")
  check(p.reason == "Not Found", "reason parsed")
  check(p.version == "HTTP/1.1", "response version parsed")
  check(headerValue(r.headers, "content-type") == "text/plain", "response header parsed")
  check(r.body == "not found", "response body parsed")

block:
  var p = newResponseParser()
  discard driveRandom(p, respMsg)
  check(p.isComplete(), "random response completes")
  check(p.toResponse().body == "not found", "random response body parsed")

# ---------------------------------------------------------------------------
# 5. No over-read: trailing (pipelined) bytes past a complete CL message are
#    left for the caller; `feed` reports exactly how much it consumed.
# ---------------------------------------------------------------------------
block:
  let trailing = "GET /next HTTP/1.1\r\n\r\n"
  let combined = reqCL & trailing
  var p = newRequestParser()
  let consumed = p.feed(combined)
  check(p.isComplete(), "first message completes from a combined buffer")
  check(consumed == reqCL.len, "feed consumed exactly the first message, no over-read")
  check(combined.len - consumed == trailing.len, "trailing bytes remain for the caller")
  # The caller can start a fresh parser on the leftover.
  var q = newRequestParser()
  var leftover = ""
  var k = consumed
  while k < combined.len:
    leftover.add combined[k]
    inc k
  discard q.feed(leftover)
  check(q.isComplete(), "leftover parses as the next (bodyless) request")
  check(q.toRequest().meth == "GET" and q.toRequest().path == "/next", "pipelined request parsed")

# ---------------------------------------------------------------------------
# 6. Partial feed reports need-more and does not fabricate completion.
# ---------------------------------------------------------------------------
block:
  var p = newRequestParser()
  discard p.feed("POST /p HTTP/1.1\r\nContent-Length: 5\r\n\r\nab")
  check(not p.isComplete(), "3 of 5 body bytes: not complete")
  check(p.needMore(), "reports need-more with body outstanding")
  discard p.feed("cde")
  check(p.isComplete(), "final body bytes complete the message")
  check(p.toRequest().body == "abcde", "streamed body reassembled")

# ---------------------------------------------------------------------------
# 7. takeBody drains incrementally without losing bytes.
# ---------------------------------------------------------------------------
block:
  var p = newRequestParser()
  discard p.feed("POST /s HTTP/1.1\r\nContent-Length: 6\r\n\r\nabc")
  let first = p.takeBody()
  check(first == "abc", "takeBody drains what has arrived")
  discard p.feed("def")
  let second = p.takeBody()
  check(second == "def", "takeBody drains the rest")
  check(p.isComplete(), "message complete after full body")
  check(p.bodyLength() == 6, "bodyLength counts all decoded bytes even after draining")

import std/syncio
echo "tstream: all checks passed"
