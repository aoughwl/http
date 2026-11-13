## http/request.aowl — tolerant HTTP/1.x request parsing.

import headers

type
  Request* = object
    ## Parsed HTTP/1.x request. `path` is the raw request-target and may include
    ## a query string.
    meth*: string
    path*: string
    version*: string
    headers*: seq[Header]
    body*: string

proc copyRange(s: string; a, b: int): string =
  ## Copy half-open [a, b) without using string slices.
  result = ""
  var i = a
  while i < b and i < s.len:
    if i >= 0: result.add s[i]
    inc i

proc readToken(raw: string; i: var int): string =
  result = ""
  while i < raw.len and raw[i] != ' ' and raw[i] != '\r' and raw[i] != '\n' and raw[i] != '\t':
    result.add raw[i]
    inc i

proc skipSpaces(raw: string; i: var int) =
  while i < raw.len and (raw[i] == ' ' or raw[i] == '\t'):
    inc i

proc lineEnd(raw: string; start: int): int =
  result = start
  while result < raw.len and raw[result] != '\r' and raw[result] != '\n':
    inc result

proc nextLine(raw: string; i: var int) =
  while i < raw.len and raw[i] != '\r' and raw[i] != '\n':
    inc i
  if i < raw.len and raw[i] == '\r':
    inc i
    if i < raw.len and raw[i] == '\n': inc i
  elif i < raw.len and raw[i] == '\n':
    inc i

proc parseRequest*(raw: string): Request =
  ## Parse request line, headers, and any bytes after the first blank line as
  ## body. Malformed/short requests return empty fields instead of raising.
  result = Request(meth: "", path: "", version: "", headers: @[], body: "")
  var i = 0
  result.meth = readToken(raw, i)
  skipSpaces(raw, i)
  result.path = readToken(raw, i)
  skipSpaces(raw, i)
  result.version = readToken(raw, i)
  nextLine(raw, i)

  var doneHeaders = false
  while i < raw.len and not doneHeaders:
    let start = i
    let stop = lineEnd(raw, start)
    if stop == start:
      doneHeaders = true
      nextLine(raw, i)
    else:
      var colon = start
      while colon < stop and raw[colon] != ':':
        inc colon
      if colon < stop:
        let name = trimHttp(copyRange(raw, start, colon))
        let value = trimHttp(copyRange(raw, colon + 1, stop))
        if name.len > 0:
          result.headers.add Header(name: name, value: value)
      i = stop
      nextLine(raw, i)

  while i < raw.len:
    result.body.add raw[i]
    inc i

proc isValidRequest*(req: Request): bool =
  req.meth.len > 0 and req.path.len > 0

proc isMethod*(req: Request; meth: string): bool =
  eqIgnoreCase(req.meth, meth)

proc headerValue*(req: Request; name: string): string =
  headerValue(req.headers, name)

proc hasHeader*(req: Request; name: string): bool =
  hasHeader(req.headers, name)

proc isTokenName(s: string): bool =
  ## RFC 7230 token: what a method or a header field name may be made of.
  if s.len == 0: return false
  var i = 0
  while i < s.len:
    let c = s[i]
    let o = ord(c)
    var ok = false
    if (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9'): ok = true
    elif o > 32 and o < 127:
      if c == '!' or c == '#' or c == '$' or c == '%' or c == '&' or c == '\'' or c == '*' or c == '+': ok = true
      elif c == '-' or c == '.' or c == '^' or c == '_' or c == '`' or c == '|' or c == '~': ok = true
    if not ok: return false
    inc i
  return true

proc hasControlByte(s: string): bool =
  ## CR, LF, NUL or any other control byte except tab, or DEL.
  var i = 0
  while i < s.len:
    let o = ord(s[i])
    if (o < 32 and o != 9) or o == 127: return true
    inc i
  return false

proc requestToString*(meth, target, host: string; headers: seq[Header]; body: string;
                      closeAfter = false): string =
  ## The bytes of one HTTP/1.1 request, with no limit on the length of the target, a header or the
  ## body. Order: request line, Host, `headers` as given, Connection: close (when `closeAfter`),
  ## Content-Length (body present, or POST/PUT/PATCH), blank line, body. The caller's Host,
  ## Content-Length, Connection and Transfer-Encoding fields are not sent (this function owns the
  ## framing). Returns "" when anything is malformed: a method or field name that is not a token,
  ## or a target, host or value with a CR, LF, NUL or other control byte (nothing can smuggle a
  ## second request or header).
  if not isTokenName(meth) or target.len == 0 or host.len == 0: return ""
  if hasControlByte(target) or hasControlByte(host) or target[0] != '/': return ""
  var wire = meth & " " & target & " HTTP/1.1\r\nHost: " & host & "\r\n"
  var i = 0
  while i < headers.len:
    let h = headers[i]
    if not isTokenName(h.name) or hasControlByte(h.value): return ""
    let low = lowerAscii(h.name)
    if low != "host" and low != "content-length" and low != "connection" and
       low != "transfer-encoding":
      wire.add h.name & ": " & h.value & "\r\n"
    inc i
  if closeAfter: wire.add "Connection: close\r\n"
  if body.len > 0 or meth == "POST" or meth == "PUT" or meth == "PATCH":
    wire.add "Content-Length: " & $body.len & "\r\n"
  wire.add "\r\n"
  wire.add body
  return wire
