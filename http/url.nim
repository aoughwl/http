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
