# http

Transport-free HTTP helpers for [Nimony](https://github.com/nim-lang/nimony):
headers, URL/query/form codecs, request parsing, typed methods and status codes,
response building, and a chunked-transfer codec. **No socket loop** — the same HTTP
layer can back any transport (it's what `serve` consumes). Status-based, nothing raises.

**📖 Full docs → [aoughwl.github.io/docs/net-stack](https://aoughwl.github.io/docs/net-stack)**

```nim
import http
```

`Header` is a plain, case-insensitive value; `HttpCode` is a `distinct int` with
`is1xx`..`is5xx` + a full RFC reason table; `parseRequest` is a pure string→`Request`
parse. Consolidates what Nim 2 splits across `std/httpcore` and `std/uri`.
