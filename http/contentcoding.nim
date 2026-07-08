## http/contentcoding.nim — HTTP `Content-Encoding` negotiation over the generic
## `compress` codecs.
##
## The raw gzip/brotli/zstd codecs live in the standalone `compress` package
## (re-exported here); this module adds only the HTTP-specific policy: turning an
## `Accept-Encoding` header into a chosen coding, and encoding/decoding a body
## for a given `Content-Encoding`.

import compress
export compress

proc containsToken(hay: string; token: string): bool =
  ## Case-insensitive substring test (Accept-Encoding lists comma-separated
  ## tokens; the coding names never collide as substrings).
  if token.len == 0: return true
  if token.len > hay.len: return false
  var i = 0
  while i + token.len <= hay.len:
    var j = 0
    var ok = true
    while j < token.len:
      var a = hay[i + j]
      var b = token[j]
      if a >= 'A' and a <= 'Z': a = chr(ord(a) + 32)
      if b >= 'A' and b <= 'Z': b = chr(ord(b) + 32)
      if a != b:
        ok = false
        break
      inc j
    if ok: return true
    inc i
  return false

proc pickEncoding*(acceptEncoding: string): string =
  ## Choose the best supported `Content-Encoding` for an `Accept-Encoding` value:
  ## prefers `br`, then `zstd`, then `gzip`, else "" (identity).
  if containsToken(acceptEncoding, "br"): return "br"
  if containsToken(acceptEncoding, "zstd"): return "zstd"
  if containsToken(acceptEncoding, "gzip"): return "gzip"
  return ""

proc encodeFor*(encoding: string; body: string): string =
  ## Encode `body` for a chosen `Content-Encoding` ("br"/"zstd"/"gzip"); returns
  ## the body unchanged for identity / unknown encodings.
  if encoding == "gzip": return gzipCompress(body)
  if encoding == "br": return brotliCompress(body)
  if encoding == "zstd": return zstdCompress(body)
  body

proc decodeFrom*(encoding: string; body: string): string =
  ## Decode a body received with the given `Content-Encoding`; body unchanged for
  ## identity / unknown encodings.
  if encoding == "gzip": return gzipDecompress(body)
  if encoding == "br": return brotliDecompress(body)
  if encoding == "zstd": return zstdDecompress(body)
  body
