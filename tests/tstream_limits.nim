## tstream_limits.nim — the StreamParser resource bounds.
##
## `maxLine` and `maxHeaderBytes` already existed. Two things were unbounded:
## the NUMBER of header fields (many tiny fields stay under maxHeaderBytes while
## still blowing up every downstream per-header loop), and the body — `feed`
## grew `bodyBuf` for as long as the peer kept sending, and a declared
## Content-Length was believed without question.

import std/syncio
import http
import http/stream

proc check(ok: bool; msg: string) =
  if not ok:
    echo "FAIL: ", msg
    quit(1)

proc feedAll(p: var StreamParser; s: string) =
  discard p.feed(s)

proc main =
  # --- defaults are readable, not baked in ------------------------------
  var d = newRequestParser()
  let lim = d.limits()
  check(lim.maxLine == 8192, "default maxLine")
  check(lim.maxHeaderBytes == 65536, "default maxHeaderBytes")
  check(lim.maxHeaderCount == 128, "default maxHeaderCount")
  check(lim.maxBody == 64 * 1024 * 1024, "default maxBody")

  # --- header COUNT is bounded independently of header BYTES ------------
  # 40 tiny fields: ~360 bytes, far under maxHeaderBytes, but over a count of 8.
  var head = "GET / HTTP/1.1\r\nHost: x\r\n"
  var i = 0
  while i < 40:
    head.add "X-"
    head.add $i
    head.add ": v\r\n"
    inc i
  head.add "\r\n"

  var pc = newRequestParser()
  pc.withBodyLimits(8, 0)
  feedAll(pc, head)
  check(pc.isError, "many tiny headers must be rejected")
  check(pc.errorStatus == 431, "expected 431, got " & $pc.errorStatus)

  # the same message is fine when the count is allowed
  var pok = newRequestParser()
  pok.withBodyLimits(128, 0)
  feedAll(pok, head)
  check(not pok.isError, "41 headers under a 128 limit must parse")
  check(pok.headComplete, "head complete")

  # --- a declared Content-Length over the cap is refused up front -------
  var pcl = newRequestParser()
  pcl.withBodyLimits(0, 1024)
  feedAll(pcl, "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 100000\r\n\r\n")
  check(pcl.isError, "oversized Content-Length must be rejected")
  check(pcl.errorStatus == 413, "expected 413, got " & $pcl.errorStatus)
  check(pcl.bodyLength == 0, "no body bytes buffered for a rejected length")

  # --- a chunked body that outgrows the cap is stopped mid-stream -------
  var pch = newRequestParser()
  pch.withBodyLimits(0, 1024)
  feedAll(pch, "POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n")
  check(not pch.isError, "chunked head parses")
  # eight 300-byte chunks = 2400 bytes, over the 1024 cap
  var chunk = "12c\r\n"          # 0x12c = 300
  var k = 0
  while k < 300:
    chunk.add 'z'
    inc k
  chunk.add "\r\n"
  var sent = 0
  while sent < 8 and not pch.isError:
    feedAll(pch, chunk)
    inc sent
  check(pch.isError, "chunked body over the cap must be rejected")
  check(pch.errorStatus == 413, "expected 413, got " & $pch.errorStatus)
  check(sent < 8, "must stop before consuming every chunk")

  # --- 0 still means unlimited ------------------------------------------
  var pun = newRequestParser()
  pun.withBodyLimits(0, 0)
  feedAll(pun, "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 100000\r\n\r\n")
  check(not pun.isError, "maxBody 0 means unlimited")

  echo "tstream_limits: all checks passed"

main()
