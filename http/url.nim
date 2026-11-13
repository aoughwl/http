## http/url.aowl — URL target, query, and form helpers.

proc pathOnly*(target: string): string =
  ## Return request-target without `?query` or `#fragment`.
  result = ""
  var i = 0
  while i < target.len and target[i] != '?' and target[i] != '#':
    result.add target[i]
    inc i

proc queryString*(target: string): string =
  ## Return the query string without the leading `?`.
  result = ""
  var i = 0
  while i < target.len and target[i] != '?':
    inc i
  if i < target.len and target[i] == '?':
    inc i
    while i < target.len and target[i] != '#':
      result.add target[i]
      inc i

proc fromHex(c: char): int =
  if c >= '0' and c <= '9': ord(c) - ord('0')
  elif c >= 'a' and c <= 'f': ord(c) - ord('a') + 10
  elif c >= 'A' and c <= 'F': ord(c) - ord('A') + 10
  else: -1

proc percentDecode*(s: string; plusAsSpace = false): string =
  ## Percent-decode a URL component. Invalid `%xx` sequences are copied as-is.
  result = ""
  var i = 0
  while i < s.len:
    # A 3-char escape starting at i needs indices i, i+1, i+2 all valid.
    # i+2 is in-bounds iff i+2 <= s.len-1, i.e. i+2 < s.len — so a valid `%xx`
    # at the very end of the string (e.g. "a%2F") decodes correctly.
    if s[i] == '%' and i + 2 < s.len:
      let hi = fromHex(s[i + 1])
      let lo = fromHex(s[i + 2])
      if hi >= 0 and lo >= 0:
        result.add chr(hi * 16 + lo)
        i = i + 3
      else:
        result.add s[i]
        inc i
    elif plusAsSpace and s[i] == '+':
      result.add ' '
      inc i
    else:
      result.add s[i]
      inc i

proc queryParam*(target, key: string): string =
  ## Return the first decoded query parameter value for `key`, or "".
  let q = queryString(target)
  var i = 0
  while i <= q.len:
    var name = ""
    var value = ""
    while i < q.len and q[i] != '=' and q[i] != '&':
      name.add q[i]
      inc i
    if i < q.len and q[i] == '=':
      inc i
      while i < q.len and q[i] != '&':
        value.add q[i]
        inc i
    if percentDecode(name, true) == key:
      return percentDecode(value, true)
    if i < q.len and q[i] == '&':
      inc i
    else:
      break
  return ""

proc formParam*(body, key: string): string =
  ## Return a value from an `application/x-www-form-urlencoded` body.
  queryParam("?" & body, key)

proc queryParams*(q: string): seq[(string, string)] =
  ## Enumerate every decoded `key`/`value` pair in query string `q` (no leading
  ## `?`). Repeated keys are all preserved, in order. `+` decodes as space.
  result = @[]
  var i = 0
  while i < q.len:
    var name = ""
    var value = ""
    while i < q.len and q[i] != '=' and q[i] != '&':
      name.add q[i]
      inc i
    if i < q.len and q[i] == '=':
      inc i
      while i < q.len and q[i] != '&':
        value.add q[i]
        inc i
    result.add (percentDecode(name, true), percentDecode(value, true))
    if i < q.len and q[i] == '&':
      inc i

proc isUnreserved(c: char): bool =
  ## RFC 3986 unreserved: ALPHA / DIGIT / "-" / "." / "_" / "~".
  (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or
  (c >= '0' and c <= '9') or c == '-' or c == '.' or c == '_' or c == '~'

proc hexDigit(n: int): char =
  if n < 10: chr(ord('0') + n) else: chr(ord('A') + n - 10)

proc percentEncode*(s: string; plusForSpace = false): string =
  ## Percent-encode every non-unreserved byte per RFC 3986. With
  ## `plusForSpace`, spaces become `+` (form encoding) instead of `%20`.
  result = ""
  var i = 0
  while i < s.len:
    let c = s[i]
    if isUnreserved(c):
      result.add c
    elif plusForSpace and c == ' ':
      result.add '+'
    else:
      let b = ord(c) and 0xFF
      result.add '%'
      result.add hexDigit(b shr 4)
      result.add hexDigit(b and 15)
    inc i

proc encodeQuery*(pairs: openArray[(string, string)]): string =
  ## Build a `k=v&k=v` query string, percent-encoding keys and values with
  ## `+` for spaces (form-urlencoded style).
  result = ""
  var i = 0
  while i < pairs.len:
    if i > 0: result.add '&'
    let p = pairs[i]
    result.add percentEncode(p[0], true)
    result.add '='
    result.add percentEncode(p[1], true)
    inc i

# --- absolute URLs (the client side) ---------------------------------------------

type
  ParsedUrl* = object
    ## `splitUrl`'s answer. `ok` false means `err` says why and nothing else is set.
    ok*: bool
    err*: string
    scheme*: string      ## lower-case: http, https, ws or wss
    secure*: bool        ## https or wss
    host*: string        ## without brackets (an IPv6 literal comes back bare)
    port*: int           ## explicit, or the scheme's default (80 / 443)
    target*: string      ## path + query, always starts with '/', fragment dropped
    hostHeader*: string  ## for the Host: line: brackets back on IPv6, ":port" only if not the default

proc urlFail(msg: string): ParsedUrl =
  ParsedUrl(ok: false, err: msg, scheme: "", secure: false, host: "", port: 0,
            target: "/", hostHeader: "")

proc lowerCopy(s: string): string =
  result = ""
  var i = 0
  while i < s.len:
    let c = s[i]
    if c >= 'A' and c <= 'Z': result.add chr(ord(c) + 32)
    else: result.add c
    inc i

proc copyBetween(s: string; a, b: int): string =
  ## [a, b)
  result = ""
  var i = a
  while i < b and i < s.len:
    result.add s[i]
    inc i

proc splitUrl*(url: string): ParsedUrl =
  ## scheme://[user@]host[:port][/path][?query][#fragment] for http, https, ws, wss. Handles IPv6
  ## literals ("[::1]:8080"), default ports, a query with no path ("http://h?x=1" -> "/?x=1") and
  ## URLs of any length. Spaces and control bytes are refused (they would break the request line).
  ## A user:password part is skipped, not returned: send credentials in a header.
  var i = 0
  while i < url.len:
    let c = ord(url[i])
    if c <= 32 or c == 127:
      return urlFail("the url contains a space or a control character")
    inc i
  var sep = -1
  i = 0
  while i + 2 < url.len and sep < 0:
    if url[i] == ':' and url[i + 1] == '/' and url[i + 2] == '/': sep = i
    inc i
  if sep <= 0: return urlFail("the url has no scheme")
  let scheme = lowerCopy(copyBetween(url, 0, sep))
  var defPort = 0
  if scheme == "http" or scheme == "ws": defPort = 80
  elif scheme == "https" or scheme == "wss": defPort = 443
  else: return urlFail("unsupported url scheme " & scheme)
  let a = sep + 3
  var e = a
  while e < url.len and url[e] != '/' and url[e] != '?' and url[e] != '#': inc e
  var auth = copyBetween(url, a, e)
  var at = -1
  var k = 0
  while k < auth.len:
    if auth[k] == '@': at = k
    inc k
  if at >= 0: auth = copyBetween(auth, at + 1, auth.len)
  var host = ""
  var portText = ""
  var v6 = false
  if auth.len > 0 and auth[0] == '[':
    var c = 1
    while c < auth.len and auth[c] != ']': inc c
    if c >= auth.len: return urlFail("the url has an unterminated IPv6 address")
    host = copyBetween(auth, 1, c)
    v6 = true
    if c + 1 < auth.len:
      if auth[c + 1] != ':': return urlFail("the url has text after the IPv6 address")
      portText = copyBetween(auth, c + 2, auth.len)
  else:
    var c = 0
    while c < auth.len and auth[c] != ':': inc c
    host = copyBetween(auth, 0, c)
    if c < auth.len: portText = copyBetween(auth, c + 1, auth.len)
  if host.len == 0: return urlFail("the url has no host")
  var port = defPort
  if portText.len > 0:
    if portText.len > 5: return urlFail("the url has an invalid port")
    var v = 0
    var j = 0
    while j < portText.len:
      let d = portText[j]
      if d < '0' or d > '9': return urlFail("the url has an invalid port")
      v = v * 10 + (ord(d) - ord('0'))
      inc j
    if v < 1 or v > 65535: return urlFail("the url has an invalid port")
    port = v
  var hh = host
  if v6: hh = "[" & host & "]"
  if port != defPort: hh = hh & ":" & $port
  var f = e
  while f < url.len and url[f] != '#': inc f
  var target = copyBetween(url, e, f)
  if target.len == 0: target = "/"
  elif target[0] == '?': target = "/" & target
  # computed before the constructor: inside it the compiled `or` of two string comparisons came out false
  var isSecure = false
  if scheme == "https": isSecure = true
  elif scheme == "wss": isSecure = true
  ParsedUrl(ok: true, err: "", scheme: scheme,
            secure: isSecure, host: host, port: port,
            target: target, hostHeader: hh)
