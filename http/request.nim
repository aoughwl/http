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
