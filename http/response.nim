## http/response.aowl — HTTP status metadata and response builders.

import headers

type
  Response* = object
    ## In-memory response model used by `responseToString`.
    status*: int
    contentType*: string
    headers*: seq[Header]
    body*: string

proc reasonPhrase*(status: int): string =
  ## Standard reason phrase for common HTTP status codes. Unknown codes return
  ## "" (never a misleading phrase such as "OK").
  case status
  of 100: "Continue"
  of 101: "Switching Protocols"
  of 200: "OK"
  of 201: "Created"
  of 202: "Accepted"
  of 203: "Non-Authoritative Information"
  of 204: "No Content"
  of 205: "Reset Content"
  of 206: "Partial Content"
  of 300: "Multiple Choices"
  of 301: "Moved Permanently"
  of 302: "Found"
  of 303: "See Other"
  of 304: "Not Modified"
  of 305: "Use Proxy"
  of 307: "Temporary Redirect"
  of 308: "Permanent Redirect"
  of 400: "Bad Request"
  of 401: "Unauthorized"
  of 402: "Payment Required"
  of 403: "Forbidden"
  of 404: "Not Found"
  of 405: "Method Not Allowed"
  of 406: "Not Acceptable"
  of 407: "Proxy Authentication Required"
  of 408: "Request Timeout"
  of 409: "Conflict"
  of 410: "Gone"
  of 411: "Length Required"
  of 412: "Precondition Failed"
  of 413: "Payload Too Large"
  of 414: "URI Too Long"
  of 415: "Unsupported Media Type"
  of 416: "Range Not Satisfiable"
  of 417: "Expectation Failed"
  of 418: "I'm a teapot"
  of 421: "Misdirected Request"
  of 422: "Unprocessable Content"
  of 423: "Locked"
  of 424: "Failed Dependency"
  of 425: "Too Early"
  of 426: "Upgrade Required"
  of 428: "Precondition Required"
  of 429: "Too Many Requests"
  of 431: "Request Header Fields Too Large"
  of 451: "Unavailable For Legal Reasons"
  of 500: "Internal Server Error"
  of 501: "Not Implemented"
  of 502: "Bad Gateway"
  of 503: "Service Unavailable"
  of 504: "Gateway Timeout"
  of 505: "HTTP Version Not Supported"
  of 506: "Variant Also Negotiates"
  of 507: "Insufficient Storage"
  of 508: "Loop Detected"
  of 510: "Not Extended"
  of 511: "Network Authentication Required"
  else: ""

type
  HttpCode* = distinct int
    ## Typed HTTP status code. `$` renders "<code> <reason>" via `reasonPhrase`.

proc code*(n: int): HttpCode =
  ## Wrap an integer status as an `HttpCode`.
  HttpCode(n)

proc toInt*(c: HttpCode): int =
  ## The underlying integer value.
  int(c)

proc `==`*(a, b: HttpCode): bool =
  int(a) == int(b)

proc is1xx*(c: HttpCode): bool = int(c) >= 100 and int(c) < 200
proc is2xx*(c: HttpCode): bool = int(c) >= 200 and int(c) < 300
proc is3xx*(c: HttpCode): bool = int(c) >= 300 and int(c) < 400
proc is4xx*(c: HttpCode): bool = int(c) >= 400 and int(c) < 500
proc is5xx*(c: HttpCode): bool = int(c) >= 500 and int(c) < 600

proc `$`*(c: HttpCode): string =
  ## "200 OK", or just the number when the code has no known reason phrase.
  let p = reasonPhrase(int(c))
  if p.len == 0: $int(c) else: $int(c) & " " & p

proc response*(status: int; contentType: string; body: string): Response =
  Response(status: status, contentType: contentType, headers: @[], body: body)

proc withHeader*(res: var Response; name, value: string) =
  res.headers.add Header(name: name, value: value)

# ---------------------------------------------------------------------------
# parsing — the mirror of `parseRequest`, for anything acting as a CLIENT
# ---------------------------------------------------------------------------

proc respLineEnd(raw: string; start: int): int =
  result = start
  while result < raw.len and raw[result] != '\r' and raw[result] != '\n':
    inc result

proc respNextLine(raw: string; i: var int) =
  while i < raw.len and raw[i] != '\r' and raw[i] != '\n':
    inc i
  if i < raw.len and raw[i] == '\r':
    inc i
    if i < raw.len and raw[i] == '\n': inc i
  elif i < raw.len and raw[i] == '\n':
    inc i

proc respCopyRange(raw: string; a, b: int): string =
  result = ""
  var i = a
  while i < b and i < raw.len:
    result.add raw[i]
    inc i

proc respTrim(s: string): string =
  var a = 0
  var b = s.len
  while a < b and (s[a] == ' ' or s[a] == '\t'): inc a
  while b > a and (s[b-1] == ' ' or s[b-1] == '\t'): dec b
  respCopyRange(s, a, b)

proc parseStatusLine*(raw: string; version: var string; status: var int;
                      reason: var string): int =
  ## Parse `HTTP/1.1 200 OK`, returning the offset just past the line (or -1 if
  ## there is no complete line yet). `status` is 0 when the line is malformed —
  ## a parser for the wire never raises, it reports.
  version = ""
  status = 0
  reason = ""
  if raw.len == 0:
    return -1
  let stop = respLineEnd(raw, 0)
  if stop >= raw.len:
    return -1                       # no line terminator yet: incomplete
  var i = 0
  while i < stop and raw[i] != ' ': inc i
  version = respCopyRange(raw, 0, i)
  while i < stop and raw[i] == ' ': inc i
  var d = 0
  var any = false
  while i < stop and raw[i] >= '0' and raw[i] <= '9':
    d = d * 10 + (ord(raw[i]) - ord('0'))
    any = true
    inc i
  if any:
    status = d
  while i < stop and raw[i] == ' ': inc i
  reason = respCopyRange(raw, i, stop)
  var k = stop
  respNextLine(raw, k)
  return k

proc parseResponse*(raw: string): Response =
  ## Parse a complete HTTP/1.x response: status line, headers, and everything
  ## after the first blank line as body. Malformed input yields empty fields
  ## rather than an error — the caller checks `status`.
  ##
  ## Transfer framing is NOT applied here: a chunked body arrives chunked, and
  ## `decodeChunked` is the caller's next step. Keeping the two apart is what
  ## lets a streaming client parse headers before the body has arrived.
  result = Response(status: 0, contentType: "", headers: @[], body: "")
  var version = ""
  var status = 0
  var reason = ""
  let afterLine = parseStatusLine(raw, version, status, reason)
  if afterLine < 0:
    return result
  result.status = status
  var i = afterLine
  var doneHeaders = false
  while i < raw.len and not doneHeaders:
    let start = i
    let stop = respLineEnd(raw, start)
    if stop == start:
      doneHeaders = true
      respNextLine(raw, i)
    else:
      var colon = start
      while colon < stop and raw[colon] != ':':
        inc colon
      if colon < stop:
        let name = respTrim(respCopyRange(raw, start, colon))
        let value = respTrim(respCopyRange(raw, colon + 1, stop))
        if name.len > 0:
          result.headers.add Header(name: name, value: value)
          if eqIgnoreCase(name, "Content-Type"):
            result.contentType = value
      i = stop
      respNextLine(raw, i)
  while i < raw.len:
    result.body.add raw[i]
    inc i

proc headerValue*(res: Response; name: string): string =
  headerValue(res.headers, name)

proc hasHeader*(res: Response; name: string): bool =
  hasHeader(res.headers, name)

proc responseHeaderEnd*(raw: string): int =
  ## Offset just past the blank line that ends the header block, or -1 while it
  ## has not arrived. A client reads until this is >= 0, then decides from
  ## `Content-Length` / `Transfer-Encoding` how much body is still owed.
  var i = 0
  while i < raw.len:
    if i + 3 < raw.len and raw[i] == '\r' and raw[i+1] == '\n' and
       raw[i+2] == '\r' and raw[i+3] == '\n':
      return i + 4
    if i + 1 < raw.len and raw[i] == '\n' and raw[i+1] == '\n':
      return i + 2
    inc i
  return -1

proc responseToString*(res: Response; includeBody = true): string =
  ## Build a complete HTTP/1.1 response. Adds `Content-Type`, `Content-Length`,
  ## and `Connection: close` unless the caller already supplied those headers.
  let bodyLen = res.body.len
  result = "HTTP/1.1 " & $res.status & " " & reasonPhrase(res.status) & "\r\n" &
           "Content-Type: " & res.contentType & "\r\n"
  var i = 0
  while i < res.headers.len:
    result.add res.headers[i].name & ": " & res.headers[i].value & "\r\n"
    inc i
  if not hasHeader(res.headers, "Content-Length"):
    result.add "Content-Length: " & $bodyLen & "\r\n"
  if not hasHeader(res.headers, "Connection"):
    result.add "Connection: close\r\n"
  result.add "\r\n"
  if includeBody:
    result.add res.body

proc httpResponse*(status: int; contentType: string; body: string): string =
  ## Backwards-compatible one-shot response builder.
  responseToString(response(status, contentType, body))

proc httpResponse*(status: int; contentType: string; body: string; headers: seq[Header]): string =
  var res = response(status, contentType, body)
  var i = 0
  while i < headers.len:
    res.headers.add headers[i]
    inc i
  responseToString(res)

proc redirect*(location: string; status = 302): string =
  var res = response(status, "text/plain", "")
  res.withHeader("Location", location)
  responseToString(res)

proc optionsResponse*(allowed: string): string =
  var res = response(204, "text/plain", "")
  res.withHeader("Allow", allowed)
  responseToString(res)

proc hexOfInt(n: int): string =
  ## Lower-case hex of a non-negative int (no "0x"), "0" for zero.
  if n <= 0: return "0"
  var v = n
  var buf = ""
  while v > 0:
    let d = v and 15
    if d < 10: buf.add chr(ord('0') + d)
    else: buf.add chr(ord('a') + d - 10)
    v = v shr 4
  # buf holds least-significant digit first; reverse it.
  result = ""
  var i = buf.len - 1
  while i >= 0:
    result.add buf[i]
    dec i

proc hexVal(c: char): int =
  if c >= '0' and c <= '9': ord(c) - ord('0')
  elif c >= 'a' and c <= 'f': ord(c) - ord('a') + 10
  elif c >= 'A' and c <= 'F': ord(c) - ord('A') + 10
  else: -1

proc encodeChunked*(body: string): string =
  ## Encode `body` as a single `Transfer-Encoding: chunked` payload followed by
  ## the zero-length terminating chunk.
  if body.len == 0:
    return "0\r\n\r\n"
  result = hexOfInt(body.len) & "\r\n" & body & "\r\n0\r\n\r\n"

proc decodeChunked*(s: string): string =
  ## Decode a `Transfer-Encoding: chunked` payload back into the raw body.
  ## Chunk extensions and a final zero chunk are handled; trailers are ignored.
  result = ""
  var i = 0
  while i < s.len:
    var size = 0
    var any = false
    while i < s.len and hexVal(s[i]) >= 0:
      size = size * 16 + hexVal(s[i])
      any = true
      inc i
    if not any: break
    # Skip any chunk extension up to the end of the size line.
    while i < s.len and s[i] != '\n':
      inc i
    if i < s.len and s[i] == '\n': inc i
    if size == 0: break
    var n = 0
    while n < size and i < s.len:
      result.add s[i]
      inc i
      inc n
    # Consume the CRLF that follows chunk data.
    if i < s.len and s[i] == '\r': inc i
    if i < s.len and s[i] == '\n': inc i
