# http

Generic HTTP helpers for nimony / Nim 3.0.

This package is deliberately transport-free: no socket loop, no filesystem
serving, and no aoughwl substrate dependency. It exists so higher-level packages
such as `serve` can share one clean HTTP layer.

```nim
import http

let req = parseRequest("GET /search?q=nimony HTTP/1.1\r\nHost: example\r\n\r\n")
assert req.isMethod("GET")
assert headerValue(req, "host") == "example"
assert queryParam(req.path, "q") == "nimony"

echo httpResponse(200, "text/plain", "ok")
```

## API

| symbol | module | role |
|--------|--------|------|
| `Header`, `header`, `headerValue`, `hasHeader` | `http/headers` | case-insensitive header helpers |
| `pathOnly`, `queryString`, `queryParam`, `formParam`, `percentDecode` | `http/url` | request-target and form decoding |
| `Request`, `parseRequest`, `isValidRequest`, `isMethod` | `http/request` | tolerant HTTP/1.x request parsing |
| `Response`, `response`, `withHeader`, `responseToString` | `http/response` | response model and serialization |
| `httpResponse`, `redirect`, `optionsResponse`, `reasonPhrase` | `http/response` | convenience response builders |

## Notes

* Standard-library only.
* Nimony-friendly: parsing char-walks rather than using string slices where
  practical because nimony string slices are `.raises`.
* Designed as a utility layer, not a complete web framework.

## License

MIT.
