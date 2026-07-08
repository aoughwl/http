# http

Transport-free HTTP helpers for [Nimony](https://github.com/nim-lang/nimony):
headers, URL/query/form codecs, request parsing, typed methods and status codes,
response building, and a chunked-transfer codec. It is the layer the
`serve` server consumes, deliberately kept out of the
`tcp → net → serve` transport chain — there is no socket loop, no filesystem
serving, and no dependency on the aoughwl socket substrate, so the same HTTP
layer can back any transport. Nimony-native, no framework runtime, string-based
values, and status-based results (nothing raises).

## Contents

- [Motivation](#motivation)
- [API](#api)
- [Layout](#layout)
- [Design notes](#design-notes)
- [Limitations](#limitations)
- [Testing](#testing)
- [Requirements](#requirements)
- [License](#license)

## Motivation

Nim 2 splits this surface across `std/httpcore` (methods, `HttpCode`, headers)
and assorted `std/uri` helpers, all written against Nim-2 semantics. `http` is a
single Nimony-native layer covering the same ground, purpose-built to be shared
by a server without dragging in a transport:

| Problem with the Nim2 stdlib path | `http`'s approach |
|-----------------------------------|-------------------|
| `std/httpcore`'s `HttpHeaders` is a raises-y `Table` wrapper | `Header` is a plain value; `header`/`headerValue`/`hasHeader` are case-insensitive and total. |
| Status codes and reasons live in `httpcore` but tangle with the async stack | `HttpCode` is a `distinct int` with `is1xx`..`is5xx` class helpers and a full RFC reason table via `reasonPhrase`. |
| URL/query/form decoding is scattered across `std/uri` and manual parsing | `pathOnly`/`queryString`/`queryParam`/`formParam` plus `percentEncode`/`percentDecode`/`encodeQuery`/`queryParams` in one module. |
| Request parsing assumes a socket and an async read loop | `parseRequest` is a pure string→`Request` parse; you own the bytes and the transport. |

## API

Everything is re-exported from `import http`. Grouped by module; ✅ marks the
current, tested surface.

### `http/headers`

| Symbol | Role | |
|--------|------|---|
| `Header`, `header` | header value type + constructor | ✅ |
| `headerValue`, `hasHeader` | case-insensitive lookup / presence | ✅ |

### `http/url`

| Symbol | Role | |
|--------|------|---|
| `pathOnly`, `queryString` | split a request-target into path and query | ✅ |
| `queryParam`, `formParam` | single-key lookup in a query / form body | ✅ |
| `queryParams` | enumerate every decoded `(key, value)` pair | ✅ |
| `percentDecode`, `percentEncode` | RFC 3986 percent codec | ✅ |
| `encodeQuery` | build an encoded `k=v&…` query string | ✅ |

### `http/httpmethod`

| Symbol | Role | |
|--------|------|---|
| `HttpMethod` | typed method enum: `HttpUnknown`, `HttpGet`, `HttpHead`, `HttpPost`, `HttpPut`, `HttpDelete`, `HttpConnect`, `HttpOptions`, `HttpTrace`, `HttpPatch` | ✅ |
| `parseHttpMethod` | tolerant, case-insensitive parse (unknown → `HttpUnknown`) | ✅ |
| `toString`, `` `$` `` | canonical upper-case token | ✅ |
| `isMethod(req, HttpMethod)` | typed method test on a parsed request | ✅ |

### `http/request`

| Symbol | Role | |
|--------|------|---|
| `Request` | parsed request (`meth`, `path`, `version`, `headers`, `body`) | ✅ |
| `parseRequest` | tolerant HTTP/1.x request parse | ✅ |
| `isValidRequest` | structural validity check | ✅ |
| `isMethod(req, string)` | case-insensitive method test | ✅ |

### `http/response`

| Symbol | Role | |
|--------|------|---|
| `Response`, `response`, `withHeader`, `responseToString` | response model, builder, header add, serialization | ✅ |
| `httpResponse`, `redirect`, `optionsResponse` | convenience response builders | ✅ |
| `HttpCode`, `code`, `toInt`, `` `$` ``, `` `==` `` | typed status code (`distinct int`) | ✅ |
| `is1xx`, `is2xx`, `is3xx`, `is4xx`, `is5xx` | status-class predicates | ✅ |
| `reasonPhrase` | full RFC reason table (see below) | ✅ |
| `encodeChunked`, `decodeChunked` | `Transfer-Encoding: chunked` codec | ✅ |

`reasonPhrase` covers the standard set: **1xx** 100 Continue, 101 Switching
Protocols · **2xx** 200 OK, 201 Created, 202 Accepted, 203 Non-Authoritative
Information, 204 No Content, 205 Reset Content, 206 Partial Content · **3xx** 300
Multiple Choices, 301 Moved Permanently, 302 Found, 303 See Other, 304 Not
Modified, 305 Use Proxy, 307 Temporary Redirect, 308 Permanent Redirect · **4xx**
400 Bad Request, 401 Unauthorized, 402 Payment Required, 403 Forbidden, 404 Not
Found, 405 Method Not Allowed, 406 Not Acceptable, 407 Proxy Authentication
Required, 408 Request Timeout, 409 Conflict, 410 Gone, 411 Length Required, 412
Precondition Failed, 413 Payload Too Large, 414 URI Too Long, 415 Unsupported
Media Type, 416 Range Not Satisfiable, 417 Expectation Failed, 418 I'm a teapot,
421 Misdirected Request, 422 Unprocessable Content, 423 Locked, 424 Failed
Dependency, 425 Too Early, 426 Upgrade Required, 428 Precondition Required, 429
Too Many Requests, 431 Request Header Fields Too Large, 451 Unavailable For Legal
Reasons · **5xx** 500 Internal Server Error, 501 Not Implemented, 502 Bad Gateway,
503 Service Unavailable, 504 Gateway Timeout, 505 HTTP Version Not Supported, 506
Variant Also Negotiates, 507 Insufficient Storage, 508 Loop Detected, 510 Not
Extended, 511 Network Authentication Required.

```nim
import http

let req = parseRequest("GET /search?q=nimony HTTP/1.1\r\nHost: example\r\n\r\n")
assert req.isMethod(HttpGet)
assert headerValue(req, "host") == "example"
assert queryParam(req.path, "q") == "nimony"

echo httpResponse(200, "text/plain", "ok")     # reasonPhrase(200) == "OK"
assert code(404).is4xx
assert decodeChunked(encodeChunked("hello world")) == "hello world"
```

## Layout

```
http/
├── http.nim            umbrella: imports and re-exports the http/ modules
├── http/
│   ├── headers.nim     Header value + case-insensitive header helpers
│   ├── url.nim         path/query split, percent codec, form + query enumeration
│   ├── httpmethod.nim  HttpMethod enum, tolerant parse, canonical tokens
│   ├── request.nim     Request model + tolerant HTTP/1.x request parsing
│   └── response.nim    Response model/builders, HttpCode + reasons, chunked codec
├── tests/
│   └── thttp.nim       behavioral smoke over headers/url/method/request/response/chunked
├── http.nimble         no third-party requires (stdlib only)
└── README.md
```

## Design notes

- **Transport-free by construction.** No socket, no file I/O, no aoughwl
  substrate dependency. `http` is a pure value/codec layer so `serve` (or any
  other transport) can share one HTTP implementation.
- **Char-walk parsing.** Parsers walk characters rather than taking string
  slices, because nimony string slices are `.raises`; this keeps the whole layer
  exception-free.
- **Typed but tolerant.** `HttpMethod` and `HttpCode` give you enums and class
  predicates, while `parseHttpMethod` and `parseRequest` stay lenient about
  malformed input (unknown method → `HttpUnknown`, not a raise).
- **Status-based, no exceptions.** Everything returns a value; validity is a
  `bool`/`HttpUnknown`, never a thrown error.

## Limitations

Scope is intentionally the HTTP grammar, not a framework:

- HTTP/1.x message grammar only — no HTTP/2 or HTTP/3 framing.
- No transport: no sockets, no TLS, no connection or request/response loop
  (that is `serve`'s job).
- No routing, middleware, cookies, or content negotiation — those belong to the
  consumer, not this layer.

## Testing

`tests/thttp.nim` is a behavioral smoke that exercises header lookup, path/query
splitting and percent decoding, `queryParams` enumeration, typed method
matching, request parsing, response building/serialization, and a
`chunked` encode/decode round-trip.

```bash
cd /home/savant/aoughwl-http
nimony c -r --path:/home/savant/aoughwl-http tests/thttp.nim   # all checks pass
```

## Requirements

A built [Nimony](https://github.com/nim-lang/nimony) toolchain providing the
`nimony` compiler on `PATH`. No third-party dependencies (stdlib only).

## License

MIT.
