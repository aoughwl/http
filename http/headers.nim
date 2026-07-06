## http/headers.aowl — small HTTP header primitives.

type
  Header* = object
    ## Header names are case-insensitive on lookup; original spelling is
    ## preserved for response emission and diagnostics.
    name*: string
    value*: string

proc header*(name, value: string): Header =
  Header(name: name, value: value)

proc asciiLower(c: char): char =
  if c >= 'A' and c <= 'Z':
    chr(ord(c) + 32)
  else:
    c

proc lowerAscii*(s: string): string =
  result = ""
  var i = 0
  while i < s.len:
    result.add asciiLower(s[i])
    inc i

proc eqIgnoreCase*(a, b: string): bool =
  if a.len != b.len: return false
  var i = 0
  while i < a.len:
    if asciiLower(a[i]) != asciiLower(b[i]): return false
    inc i
  return true

proc trimHttp*(s: string): string =
  ## Trim spaces and horizontal tabs from both ends.
  var first = 0
  while first < s.len and (s[first] == ' ' or s[first] == '\t'):
    inc first
  var last = s.len - 1
  while last >= first and (s[last] == ' ' or s[last] == '\t'):
    dec last
  result = ""
  var i = first
  while i <= last:
    result.add s[i]
    inc i

proc headerValue*(headers: seq[Header]; name: string): string =
  ## Return the first matching header value, or "" if absent.
  var i = 0
  while i < headers.len:
    if eqIgnoreCase(headers[i].name, name):
      return headers[i].value
    inc i
  return ""

proc hasHeader*(headers: seq[Header]; name: string): bool =
  headerValue(headers, name).len > 0
