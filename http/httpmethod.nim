## http/httpmethod.aowl — typed HTTP request methods.

import headers
import request

type
  HttpMethod* = enum
    ## Typed request method. `HttpUnknown` is returned by `parseHttpMethod`
    ## for anything not in the standard RFC 7231 / RFC 5789 set.
    HttpUnknown, HttpGet, HttpHead, HttpPost, HttpPut, HttpDelete,
    HttpConnect, HttpOptions, HttpTrace, HttpPatch

proc toString*(m: HttpMethod): string =
  ## Canonical upper-case token for `m`; "" for `HttpUnknown`.
  case m
  of HttpGet: "GET"
  of HttpHead: "HEAD"
  of HttpPost: "POST"
  of HttpPut: "PUT"
  of HttpDelete: "DELETE"
  of HttpConnect: "CONNECT"
  of HttpOptions: "OPTIONS"
  of HttpTrace: "TRACE"
  of HttpPatch: "PATCH"
  of HttpUnknown: ""

proc `$`*(m: HttpMethod): string =
  toString(m)

proc parseHttpMethod*(s: string): HttpMethod =
  ## Tolerant, case-insensitive parse. Unrecognized tokens map to `HttpUnknown`.
  if eqIgnoreCase(s, "GET"): HttpGet
  elif eqIgnoreCase(s, "HEAD"): HttpHead
  elif eqIgnoreCase(s, "POST"): HttpPost
  elif eqIgnoreCase(s, "PUT"): HttpPut
  elif eqIgnoreCase(s, "DELETE"): HttpDelete
  elif eqIgnoreCase(s, "CONNECT"): HttpConnect
  elif eqIgnoreCase(s, "OPTIONS"): HttpOptions
  elif eqIgnoreCase(s, "TRACE"): HttpTrace
  elif eqIgnoreCase(s, "PATCH"): HttpPatch
  else: HttpUnknown

proc isMethod*(req: Request; m: HttpMethod): bool =
  ## Typed counterpart to `isMethod(req, string)`.
  parseHttpMethod(req.meth) == m
