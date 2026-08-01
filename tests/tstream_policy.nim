## tstream_policy.nim — ParserLimits as a value, and the chunk-size bound.
##
## Two things are under test. First, that a parsing policy can be *described*
## and handed to whatever builds the parser, rather than only adjusted on a
## parser you already hold — a server builds its own parsers, so the caller who
## wants to bound them has no other way in.
##
## Second, the chunk-size accumulator. The size was parsed hex digit by hex
## digit with no bound on the running total, so a chunk header of sixteen 'f's
## overflowed to a negative number and the framing below read that as a short
## chunk. Bounding the *result* would not have caught it; the bound has to be
## inside the accumulation loop, which is what `maxChunkSize` does.

import std/syncio
import http
import http/stream

proc check(ok: bool; msg: string) =
  if not ok:
    echo "FAIL: ", msg
    quit(1)

proc main =
  # --- three states, and the difference between two of them --------------
  check(LimitUnset != Unlimited,
        "unset and unlimited must be distinguishable")
  check(not exceeds(Unlimited, 1_000_000_000), "Unlimited never trips")
  check(not exceeds(LimitUnset, 1_000_000_000), "an unset limit never trips")
  check(exceeds(10, 11), "a positive limit trips when passed")
  check(not exceeds(10, 10), "a positive limit does not trip at the boundary")

  # --- merge, and why unset must not collapse into unlimited -------------
  var override = noParserLimits()
  override.maxBody = 512 * 1024 * 1024
  let merged = merge(defaultParserLimits(), override)
  check(merged.maxBody == 512 * 1024 * 1024, "the set field overrides")
  check(merged.maxLine == DefaultMaxLine,
        "raising one bound must not silently remove the others")
  check(merged.maxHeaderCount == DefaultMaxHeaderCount, "and not this one either")

  var uncapped = noParserLimits()
  uncapped.maxBody = Unlimited
  let unbounded = merge(defaultParserLimits(), uncapped)
  check(unbounded.maxBody == Unlimited,
        "Unlimited is a set value and does override")
  check(unbounded.maxLine == DefaultMaxLine, "and overrides only itself")

  # --- a parser built from a policy --------------------------------------
  var strict = defaultParserLimits()
  strict.maxHeaderCount = 4
  strict.maxChunkSize = 64
  var p = newRequestParser(strict)
  check(p.limits().maxHeaderCount == 4, "the policy reached the parser")
  check(p.limits().maxLine == DefaultMaxLine, "unmentioned bounds kept their default")

  # It is enforced, not merely stored.
  var head = "GET / HTTP/1.1\r\nHost: x\r\nA: 1\r\nB: 2\r\nC: 3\r\nD: 4\r\nE: 5\r\n\r\n"
  discard p.feed(head)
  check(p.state == ssError, "the header-count policy is enforced")
  check(p.errorStatus == 431, "and answers 431")

  # --- the chunk-size accumulator ----------------------------------------
  # A size within the bound is accepted and framed normally.
  var okp = newRequestParser(strict)
  discard okp.feed("POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n")
  discard okp.feed("4\r\nabcd\r\n0\r\n\r\n")
  check(okp.state == ssComplete, "a chunk inside the bound still parses")
  check(okp.takeBody() == "abcd", "and its bytes survive")

  # A size over the bound is refused.
  var bigp = newRequestParser(strict)
  discard bigp.feed("POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n")
  discard bigp.feed("100\r\n")          # 256 bytes, over maxChunkSize = 64
  check(bigp.state == ssError, "an oversized chunk is refused")
  check(bigp.errorStatus == 413, "and answers 413")

  # The overflow case: sixteen 'f' digits. Under the old accumulator this
  # wrapped to a negative size and was read as a short chunk, so the message
  # framed "successfully" against a length the peer never sent.
  var ovp = newRequestParser()          # stock limits, not the strict ones
  discard ovp.feed("POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n")
  discard ovp.feed("ffffffffffffffff\r\n")
  check(ovp.state == ssError,
        "a chunk size that overflows the accumulator is refused")
  check(ovp.errorStatus == 413, "and answers 413, not a silent short chunk")

  # And with the bound deliberately removed, the overflow guard still holds:
  # `size < 0` is not a limit question, it is an arithmetic one.
  var freep = newRequestParser(unboundedParserLimits())
  discard freep.feed("POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n")
  discard freep.feed("ffffffffffffffff\r\n")
  check(freep.state == ssError,
        "removing the limit does not re-enable the overflow")

  echo "tstream_policy: all checks passed"

main()
