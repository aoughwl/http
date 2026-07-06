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
  ## Standard reason phrase for common HTTP status codes.
  case status
  of 200: "OK"
  of 201: "Created"
  of 202: "Accepted"
  of 204: "No Content"
  of 206: "Partial Content"
  of 301: "Moved Permanently"
  of 302: "Found"
  of 303: "See Other"
  of 304: "Not Modified"
  of 307: "Temporary Redirect"
  of 308: "Permanent Redirect"
  of 400: "Bad Request"
  of 401: "Unauthorized"
  of 403: "Forbidden"
  of 404: "Not Found"
  of 405: "Method Not Allowed"
  of 409: "Conflict"
  of 410: "Gone"
  of 413: "Payload Too Large"
  of 415: "Unsupported Media Type"
  of 418: "I'm a teapot"
  of 422: "Unprocessable Content"
  of 429: "Too Many Requests"
  of 500: "Internal Server Error"
  of 501: "Not Implemented"
  of 502: "Bad Gateway"
  of 503: "Service Unavailable"
  else: "OK"

proc response*(status: int; contentType: string; body: string): Response =
  Response(status: status, contentType: contentType, headers: @[], body: body)

proc withHeader*(res: var Response; name, value: string) =
  res.headers.add Header(name: name, value: value)

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
