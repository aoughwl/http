## http/stream.aowl — resumable, transport-free incremental HTTP/1.x parser.
##
## The one-shot `parseRequest` / helpers in this pack operate on a WHOLE
## message that has already been buffered. `StreamParser` closes that gap: a
## caller that receives HTTP in arbitrary chunks (mid-line, mid-header,
## mid-chunk-size, mid-body) feeds each chunk into `feed` as it arrives and the
## parser advances through the request/response line, the header block, and the
## body without ever needing the complete message in one string.
##
## Design:
## * Char-walked. No string slices (which `.raise` under nimony), no exceptions.
## * Caller-owned buffering: `feed` returns how many bytes it consumed, so a
##   caller keeps ownership of anything past the end of a message (HTTP
##   pipelining) and the parser never over-reads.
## * Body framing supports `Content-Length`, `Transfer-Encoding: chunked`
##   (de-chunked in place), and — for responses — read-until-close via `finish`.
## * Sane limits (max request/status line, max header-block) surface as a
##   status-based error (`errorStatus`), never a raised exception.
##
## The parsed head is exposed both as loose fields and, for convenience/parity
## with the one-shot API, via `toRequest` / `toResponse`. Decoded body bytes are
## accumulated and can be pulled incrementally with `takeBody`.

import headers
import request
import response

type
  StreamKind* = enum
    ## Which grammar the first line follows.
    skRequest, skResponse

  StreamState* = enum
    ## Where the parser currently sits in the message.
    ssLine,          ## accumulating the request-line / status-line
    ssHeaders,       ## accumulating header lines until the blank line
    ssBody,          ## Content-Length (or read-until-close) body
    ssChunkSize,     ## accumulating a chunk-size line
    ssChunkData,     ## copying chunk-data bytes
    ssChunkDataEnd,  ## consuming the CRLF that follows chunk-data
    ssTrailer,       ## consuming trailer lines after the final zero chunk
    ssComplete,      ## whole message parsed
    ssError          ## unrecoverable framing/limit error

  StreamParser* = object
    kind: StreamKind
    state*: StreamState
    lineBuf: string          ## bytes of the current line, CR/LF excluded
    headerBytes: int         ## running size of the header block (limit guard)
    maxLine: int             ## max bytes in any single line
    maxHeaderBytes: int      ## max total header-block size
    # --- parsed head ---
    meth*: string            ## request method (request only)
    target*: string          ## request-target/path (request only)
    version*: string         ## HTTP version token, both kinds
    status*: int             ## status code (response only)
    reason*: string          ## reason phrase (response only)
    headers*: seq[Header]
    headComplete*: bool      ## request/status line + headers fully parsed
    # --- body framing ---
    chunked: bool
    eofDelimited: bool       ## response body ends at connection close
    remaining: int           ## bytes still expected in body / current chunk
    bodyBuf: string          ## decoded body bytes not yet taken by the caller
    bodyTotal: int           ## total decoded body bytes seen (for parity checks)
    # --- terminal status ---
    errorStatus*: int        ## 0 when healthy; else an HTTP status code
    errorMsg*: string

proc initParser(kind: StreamKind): StreamParser =
  result = StreamParser(
    kind: kind, state: ssLine, lineBuf: "", headerBytes: 0,
    maxLine: 8192, maxHeaderBytes: 65536,
    meth: "", target: "", version: "", status: 0, reason: "",
    headers: @[], headComplete: false,
    chunked: false, eofDelimited: false, remaining: 0,
    bodyBuf: "", bodyTotal: 0, errorStatus: 0, errorMsg: "")

proc newRequestParser*(): StreamParser =
  ## A parser that expects an HTTP request (method / target / version first).
  initParser(skRequest)

proc newResponseParser*(): StreamParser =
  ## A parser that expects an HTTP response (version / status / reason first).
  initParser(skResponse)

proc withLimits*(p: var StreamParser; maxLine, maxHeaderBytes: int) =
  ## Override the default line (8192) and header-block (65536) byte limits.
  if maxLine > 0: p.maxLine = maxLine
  if maxHeaderBytes > 0: p.maxHeaderBytes = maxHeaderBytes

# --- small char helpers (no slices, no raises) -------------------------------

proc hexDigit(c: char): int =
  if c >= '0' and c <= '9': ord(c) - ord('0')
  elif c >= 'a' and c <= 'f': ord(c) - ord('a') + 10
  elif c >= 'A' and c <= 'F': ord(c) - ord('A') + 10
  else: -1

proc parseDecimal(s: string; ok: var bool): int =
  ## Parse a non-negative decimal with optional surrounding whitespace.
  ok = false
  result = 0
  var i = 0
  while i < s.len and (s[i] == ' ' or s[i] == '\t'):
    inc i
  var any = false
  while i < s.len and s[i] >= '0' and s[i] <= '9':
    result = result * 10 + (ord(s[i]) - ord('0'))
    any = true
    inc i
  while i < s.len and (s[i] == ' ' or s[i] == '\t'):
    inc i
  if any and i >= s.len:
    ok = true

proc containsCI(hay, needle: string): bool =
  ## Case-insensitive substring test (needle assumed already lower-case).
  if needle.len == 0: return true
  if needle.len > hay.len: return false
  let low = lowerAscii(hay)
  var i = 0
  while i + needle.len <= low.len:
    var j = 0
    var okk = true
    while j < needle.len:
      if low[i + j] != needle[j]:
        okk = false
        break
      inc j
    if okk: return true
    inc i
  return false

proc setError(p: var StreamParser; status: int; msg: string) =
  p.state = ssError
  p.errorStatus = status
  p.errorMsg = msg

# --- head parsing ------------------------------------------------------------

proc parseRequestLine(p: var StreamParser) =
  let raw = p.lineBuf
  var i = 0
  # method
  while i < raw.len and raw[i] != ' ':
    p.meth.add raw[i]
    inc i
  while i < raw.len and raw[i] == ' ': inc i
  # target
  while i < raw.len and raw[i] != ' ':
    p.target.add raw[i]
    inc i
  while i < raw.len and raw[i] == ' ': inc i
  # version
  while i < raw.len and raw[i] != ' ':
    p.version.add raw[i]
    inc i
  if p.meth.len == 0 or p.target.len == 0:
    setError(p, 400, "malformed request line")

proc parseStatusLine(p: var StreamParser) =
  let raw = p.lineBuf
  var i = 0
  # version
  while i < raw.len and raw[i] != ' ':
    p.version.add raw[i]
    inc i
  while i < raw.len and raw[i] == ' ': inc i
  # status code (exactly the digits)
  var any = false
  while i < raw.len and raw[i] >= '0' and raw[i] <= '9':
    p.status = p.status * 10 + (ord(raw[i]) - ord('0'))
    any = true
    inc i
  while i < raw.len and raw[i] == ' ': inc i
  # reason phrase = rest of line
  while i < raw.len:
    p.reason.add raw[i]
    inc i
  if p.version.len == 0 or not any:
    setError(p, 400, "malformed status line")

proc beginBody(p: var StreamParser) =
  ## Decide body framing once the header block is complete.
  p.headComplete = true
  let te = headerValue(p.headers, "Transfer-Encoding")
  if te.len > 0 and containsCI(te, "chunked"):
    p.chunked = true
    p.lineBuf = ""
    p.state = ssChunkSize
    return
  let cl = headerValue(p.headers, "Content-Length")
  if cl.len > 0:
    var ok = false
    let n = parseDecimal(cl, ok)
    if not ok or n < 0:
      setError(p, 400, "bad Content-Length")
      return
    p.remaining = n
    if n == 0:
      p.state = ssComplete
    else:
      p.state = ssBody
    return
  # No explicit framing.
  if p.kind == skRequest:
    # A request without Content-Length / chunked carries no body.
    p.state = ssComplete
  else:
    # A response body runs until the connection closes.
    p.eofDelimited = true
    p.state = ssBody

proc parseHeaderLine(p: var StreamParser) =
  let raw = p.lineBuf
  var colon = 0
  while colon < raw.len and raw[colon] != ':':
    inc colon
  if colon < raw.len:
    var name = ""
    var k = 0
    while k < colon:
      name.add raw[k]
      inc k
    var value = ""
    k = colon + 1
    while k < raw.len:
      value.add raw[k]
      inc k
    let tn = trimHttp(name)
    let tv = trimHttp(value)
    if tn.len > 0:
      p.headers.add Header(name: tn, value: tv)
  # A line with no colon is tolerated (ignored), matching parseRequest.

proc processLine(p: var StreamParser) =
  ## Dispatch a just-completed line (in `p.lineBuf`) by current state.
  case p.state
  of ssLine:
    if p.kind == skRequest: parseRequestLine(p)
    else: parseStatusLine(p)
    if p.state != ssError:
      p.state = ssHeaders
  of ssHeaders:
    if p.lineBuf.len == 0:
      beginBody(p)
    else:
      p.headerBytes = p.headerBytes + p.lineBuf.len + 2
      if p.headerBytes > p.maxHeaderBytes:
        setError(p, 431, "header block too large")
      else:
        parseHeaderLine(p)
  of ssChunkSize:
    var size = 0
    var any = false
    var i = 0
    while i < p.lineBuf.len:
      let d = hexDigit(p.lineBuf[i])
      if d < 0: break
      size = size * 16 + d
      any = true
      inc i
    if not any:
      setError(p, 400, "bad chunk size")
    elif size == 0:
      # Final chunk: consume trailers up to the next blank line.
      p.state = ssTrailer
    else:
      p.remaining = size
      p.state = ssChunkData
  of ssTrailer:
    if p.lineBuf.len == 0:
      p.state = ssComplete
    # else: trailer header line, ignored.
  else:
    discard

# --- feed --------------------------------------------------------------------

proc lineState(s: StreamState): bool =
  s == ssLine or s == ssHeaders or s == ssChunkSize or s == ssTrailer

proc feed*(p: var StreamParser; data: string): int =
  ## Feed the next chunk of received bytes. Returns the number of bytes
  ## consumed from `data`; any remainder (only possible once the message is
  ## complete) is the caller's — the parser never over-reads. Safe to call with
  ## a single byte, the whole message, or anything in between.
  var i = 0
  while i < data.len and p.state != ssError and p.state != ssComplete:
    if lineState(p.state):
      let c = data[i]
      inc i
      if c == '\n':
        processLine(p)
        p.lineBuf = ""
      elif c == '\r':
        discard  # CR is a line-ending artifact; real content has no bare CR
      else:
        p.lineBuf.add c
        if p.lineBuf.len > p.maxLine:
          setError(p, 431, "line too long")
    elif p.state == ssBody:
      if p.eofDelimited:
        # Consume everything available; completion happens on `finish`.
        while i < data.len:
          p.bodyBuf.add data[i]
          p.bodyTotal = p.bodyTotal + 1
          inc i
      else:
        while i < data.len and p.remaining > 0:
          p.bodyBuf.add data[i]
          p.bodyTotal = p.bodyTotal + 1
          inc i
          dec p.remaining
        if p.remaining == 0:
          p.state = ssComplete
    elif p.state == ssChunkData:
      while i < data.len and p.remaining > 0:
        p.bodyBuf.add data[i]
        p.bodyTotal = p.bodyTotal + 1
        inc i
        dec p.remaining
      if p.remaining == 0:
        p.state = ssChunkDataEnd
    elif p.state == ssChunkDataEnd:
      let c = data[i]
      inc i
      if c == '\n':
        p.lineBuf = ""
        p.state = ssChunkSize
      # ignore \r (and tolerate a lone \n)
    else:
      discard
  return i

proc finish*(p: var StreamParser) =
  ## Signal end-of-input (connection closed). Completes a read-until-close
  ## response body; on any other incomplete state records a truncation error.
  if p.state == ssComplete or p.state == ssError:
    return
  if p.state == ssBody and p.eofDelimited:
    p.state = ssComplete
  else:
    setError(p, 400, "truncated message")

# --- queries -----------------------------------------------------------------

proc isComplete*(p: StreamParser): bool =
  ## The whole message has been parsed.
  p.state == ssComplete

proc isError*(p: StreamParser): bool =
  ## An unrecoverable framing/limit error occurred.
  p.state == ssError

proc needMore*(p: StreamParser): bool =
  ## The parser is healthy but waiting for more bytes.
  p.state != ssComplete and p.state != ssError

proc takeBody*(p: var StreamParser): string =
  ## Pull and clear the decoded body bytes accumulated so far. Call repeatedly
  ## while streaming a large body; call once at the end for a small one.
  result = p.bodyBuf
  p.bodyBuf = ""

proc bodyLength*(p: StreamParser): int =
  ## Total decoded body bytes seen so far (including any already taken).
  p.bodyTotal

proc headerValue*(p: StreamParser; name: string): string =
  ## First matching header value from the parsed head, or "".
  headerValue(p.headers, name)

proc toRequest*(p: StreamParser): Request =
  ## Snapshot the parsed request head plus any un-taken body bytes as a
  ## `Request`, matching the shape produced by the one-shot `parseRequest`.
  Request(meth: p.meth, path: p.target, version: p.version,
          headers: p.headers, body: p.bodyBuf)

proc toResponse*(p: StreamParser): Response =
  ## Snapshot the parsed response head plus any un-taken body bytes as a
  ## `Response`.
  Response(status: p.status, contentType: headerValue(p.headers, "Content-Type"),
           headers: p.headers, body: p.bodyBuf)
