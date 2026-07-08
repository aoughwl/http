## http/compress.nim — HTTP content coding over zlib (`libz.so.1`) and, when
## available, Brotli (`libbrotlienc`/`libbrotlidec`).
##
## `gzipCompress` / `gzipDecompress` produce and consume the gzip wire format
## (`Content-Encoding: gzip`), the universally-accepted HTTP codec.
## `brotliCompress` / `brotliDecompress` handle `Content-Encoding: br`.
## Everything is one-shot over in-memory strings — no streaming state — matching
## the rest of the transport-free `http` layer.

const
  zlib = "libz.so.1"
  brotliEnc = "libbrotlienc.so.1"
  brotliDec = "libbrotlidec.so.1"

# ---------------------------------------------------------------------------
# zlib (gzip)
# ---------------------------------------------------------------------------

type
  ZStream = object
    ## Matches the C `z_stream` layout on LP64 (size 112).
    nextIn: nil pointer      # 0
    availIn: uint32          # 8
    totalIn: uint            # 16
    nextOut: nil pointer     # 24
    availOut: uint32         # 32
    totalOut: uint           # 40
    msg: nil pointer         # 48
    state: nil pointer       # 56
    zalloc: nil pointer      # 64
    zfree: nil pointer       # 72
    opaque: nil pointer      # 80
    dataType: int32          # 88
    adler: uint              # 96
    reserved: uint           # 104

proc deflateInit2Raw(strm: ptr ZStream; level, meth, windowBits, memLevel, strategy: cint;
                   version: cstring; streamSize: cint): cint {.cdecl, importc: "deflateInit2_", dynlib: zlib.}
proc deflate(strm: ptr ZStream; flush: cint): cint {.cdecl, importc: "deflate", dynlib: zlib.}
proc deflateEnd(strm: ptr ZStream): cint {.cdecl, importc: "deflateEnd", dynlib: zlib.}
proc inflateInit2Raw(strm: ptr ZStream; windowBits: cint; version: cstring;
                   streamSize: cint): cint {.cdecl, importc: "inflateInit2_", dynlib: zlib.}
proc inflate(strm: ptr ZStream; flush: cint): cint {.cdecl, importc: "inflate", dynlib: zlib.}
proc inflateEnd(strm: ptr ZStream): cint {.cdecl, importc: "inflateEnd", dynlib: zlib.}
proc zlibVersion(): cstring {.cdecl, importc: "zlibVersion", dynlib: zlib.}

const
  Z_FINISH = cint(4)
  Z_NO_FLUSH = cint(0)
  Z_OK = cint(0)
  Z_STREAM_END = cint(1)
  Z_DEFLATED = cint(8)
  GZIP_WINDOW = cint(31)   # 15 (max window) + 16 (gzip wrapper)

proc gzipCompress*(data: string; level = 6): string =
  ## Compress `data` into the gzip format (`Content-Encoding: gzip`). "" on error.
  result = ""
  var strm = default(ZStream)
  if deflateInit2Raw(addr strm, cint(level), Z_DEFLATED, GZIP_WINDOW, cint(8), cint(0),
                   zlibVersion(), cint(sizeof(ZStream))) != Z_OK:
    return ""
  var inCopy = data
  if data.len > 0:
    strm.nextIn = cast[pointer](toCString(inCopy))
  else:
    strm.nextIn = cast[pointer](0)
  strm.availIn = uint32(data.len)
  var outBuf = default(array[16384, char])
  while true:
    strm.nextOut = addr outBuf[0]
    strm.availOut = uint32(outBuf.len)
    let rc = deflate(addr strm, Z_FINISH)
    let produced = outBuf.len - int(strm.availOut)
    var i = 0
    while i < produced:
      result.add outBuf[i]
      inc i
    if rc == Z_STREAM_END:
      break
    if rc < Z_OK:
      discard deflateEnd(addr strm)
      return ""
  discard deflateEnd(addr strm)

proc gzipDecompress*(data: string): string =
  ## Decompress a gzip (or zlib) payload. "" on error.
  result = ""
  if data.len == 0: return ""
  var strm = default(ZStream)
  # windowBits 15+32 → auto-detect gzip or zlib header.
  if inflateInit2Raw(addr strm, cint(47), zlibVersion(), cint(sizeof(ZStream))) != Z_OK:
    return ""
  var inCopy = data
  strm.nextIn = cast[pointer](toCString(inCopy))
  strm.availIn = uint32(data.len)
  var outBuf = default(array[16384, char])
  while true:
    strm.nextOut = addr outBuf[0]
    strm.availOut = uint32(outBuf.len)
    let rc = inflate(addr strm, Z_NO_FLUSH)
    let produced = outBuf.len - int(strm.availOut)
    var i = 0
    while i < produced:
      result.add outBuf[i]
      inc i
    if rc == Z_STREAM_END:
      break
    if rc < Z_OK:
      discard inflateEnd(addr strm)
      return ""
    if strm.availIn == 0'u32 and produced == 0:
      break
  discard inflateEnd(addr strm)

# ---------------------------------------------------------------------------
# Brotli
# ---------------------------------------------------------------------------

proc BrotliEncoderCompress(quality, lgwin, mode: cint; inputSize: csize_t; input: pointer;
                           encodedSize: ptr csize_t; encoded: pointer): cint {.cdecl, importc: "BrotliEncoderCompress", dynlib: brotliEnc.}
proc BrotliEncoderMaxCompressedSize(inputSize: csize_t): csize_t {.cdecl, importc: "BrotliEncoderMaxCompressedSize", dynlib: brotliEnc.}
proc BrotliDecoderDecompress(encodedSize: csize_t; encoded: pointer;
                             decodedSize: ptr csize_t; decoded: pointer): cint {.cdecl, importc: "BrotliDecoderDecompress", dynlib: brotliDec.}

const
  BROTLI_MODE_GENERIC = cint(0)
  BROTLI_DECODER_RESULT_SUCCESS = cint(1)

proc brotliCompress*(data: string; quality = 5): string =
  ## Compress `data` with Brotli (`Content-Encoding: br`). "" on error.
  result = ""
  let cap = int(BrotliEncoderMaxCompressedSize(csize_t(data.len)))
  if cap <= 0: return ""
  var outBuf = newString(cap)
  var outLen = csize_t(cap)
  var inCopy = data
  var inPtr = cast[pointer](0)
  if data.len > 0: inPtr = cast[pointer](toCString(inCopy))
  let rc = BrotliEncoderCompress(cint(quality), cint(22), BROTLI_MODE_GENERIC,
                                 csize_t(data.len), inPtr, addr outLen,
                                 cast[pointer](toCString(outBuf)))
  if rc == cint(0): return ""
  result = ""
  let a = cast[ptr UncheckedArray[char]](toCString(outBuf))
  var i = 0
  while i < int(outLen):
    result.add a[i]
    inc i

proc brotliDecompress*(data: string; maxSize = 16 * 1024 * 1024): string =
  ## Decompress a Brotli payload, bounded by `maxSize`. "" on error.
  result = ""
  if data.len == 0: return ""
  var outBuf = newString(maxSize)
  var outLen = csize_t(maxSize)
  var inCopy = data
  let rc = BrotliDecoderDecompress(csize_t(data.len), cast[pointer](toCString(inCopy)),
                                   addr outLen, cast[pointer](toCString(outBuf)))
  if rc != BROTLI_DECODER_RESULT_SUCCESS: return ""
  result = ""
  let a = cast[ptr UncheckedArray[char]](toCString(outBuf))
  var i = 0
  while i < int(outLen):
    result.add a[i]
    inc i

# ---------------------------------------------------------------------------
# Content-Encoding negotiation
# ---------------------------------------------------------------------------

proc pickEncoding*(acceptEncoding: string): string =
  ## Choose the best supported `Content-Encoding` for an `Accept-Encoding`
  ## header value: prefers `br`, then `gzip`, else "" (identity).
  var hasBr = false
  var hasGzip = false
  var i = 0
  let n = acceptEncoding.len
  while i < n:
    # crude token scan (case-insensitive), enough for real Accept-Encoding lists.
    if i + 2 <= n and (acceptEncoding[i] == 'b' or acceptEncoding[i] == 'B') and
       (acceptEncoding[i+1] == 'r' or acceptEncoding[i+1] == 'R'):
      hasBr = true
    if i + 4 <= n and (acceptEncoding[i] == 'g' or acceptEncoding[i] == 'G'):
      hasGzip = true
    inc i
  if hasBr: return "br"
  if hasGzip: return "gzip"
  return ""

proc encodeFor*(encoding: string; body: string): string =
  ## Encode `body` for a chosen `Content-Encoding` ("br" / "gzip"); returns the
  ## body unchanged for identity / unknown encodings.
  if encoding == "gzip": return gzipCompress(body)
  if encoding == "br": return brotliCompress(body)
  body
