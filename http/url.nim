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
