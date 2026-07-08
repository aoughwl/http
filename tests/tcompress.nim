## tcompress.nim — gzip + Brotli round-trips and Content-Encoding negotiation.

import std/syncio
import http/compress

proc check(cond: bool; msg: string) =
  if not cond:
    echo "FAIL: ", msg
    quit(1)

proc sample(): string =
  # Repetitive, compressible text so the codec has something to do.
  result = ""
  var i = 0
  while i < 500:
    result.add "the quick brown fox jumps over the lazy dog. "
    inc i

proc main =
  let original = sample()

  # gzip round-trip; the compressed form must be much smaller and a valid gzip
  # payload (starts with the 1f 8b magic).
  let gz = gzipCompress(original)
  check(gz.len > 2, "gzip produced nothing")
  check(gz.len < original.len, "gzip did not shrink the payload")
  check(uint8(ord(gz[0])) == 0x1f'u8 and uint8(ord(gz[1])) == 0x8b'u8, "not a gzip stream")
  let gzBack = gzipDecompress(gz)
  check(gzBack == original, "gzip round-trip mismatch (" & $gzBack.len & " vs " & $original.len & ")")
  echo "gzip: ", original.len, " -> ", gz.len, " -> ", gzBack.len

  # Brotli round-trip.
  let br = brotliCompress(original)
  check(br.len > 0, "brotli produced nothing")
  check(br.len < original.len, "brotli did not shrink the payload")
  let brBack = brotliDecompress(br)
  check(brBack == original, "brotli round-trip mismatch")
  echo "br:   ", original.len, " -> ", br.len, " -> ", brBack.len

  # Negotiation.
  check(pickEncoding("gzip, deflate, br") == "br", "should prefer br")
  check(pickEncoding("gzip, deflate") == "gzip", "should pick gzip")
  check(pickEncoding("identity") == "", "identity → no encoding")
  check(encodeFor("gzip", original) == gz or gzipDecompress(encodeFor("gzip", original)) == original,
        "encodeFor gzip mismatch")

  echo "tcompress: all checks passed"

main()
