## http/parserlimits.nim — the HTTP parser's resource bounds, as a record.
##
## The bounds themselves already existed as private fields with two `with*`
## setters. What did not exist was a *value*: a caller could adjust a parser it
## held, but could not describe a parsing policy and hand it to something that
## builds parsers on its behalf — which is every server in the stack. This is
## that value.
##
## Three states per field, and the difference between the last two matters:
##
##   `LimitUnset` (-1)  inherit — used by an override record, never a live one
##   `Unlimited`  (0)   no bound at all, deliberately
##   any positive       the bound, in bytes or in count
##
## Collapsing "unset" into "unlimited" is the mistake this avoids: an override
## that only wanted to raise `maxBody` would otherwise silently remove every
## other bound.

const
  LimitUnset* = -1
    ## In an override record: inherit this field from the base.
  Unlimited* = 0
    ## No bound. A deliberate choice, distinct from "not mentioned".

  DefaultMaxLine* = 8192
    ## Request/status line and any single header line.
  DefaultMaxHeaderBytes* = 65536
    ## Whole header block.
  DefaultMaxHeaderCount* = 128
    ## Number of header fields. Many tiny fields stay under the byte limit
    ## while still costing a slot each, so the count needs its own bound.
  DefaultMaxBody* = 64 * 1024 * 1024
    ## Decoded body bytes.
  DefaultMaxChunkSize* = 16 * 1024 * 1024
    ## The size a single chunk header may declare.

type
  ParserLimits* = object
    ## What a parser will accept before it refuses the message. Every field is
    ## public and every default is a named constant above, so "the defaults but
    ## with a bigger body" does not mean re-hardcoding the other four.
    maxLine*: int
    maxHeaderBytes*: int
    maxHeaderCount*: int
    maxBody*: int
    maxChunkSize*: int

proc defaultParserLimits*(): ParserLimits =
  ## The bounds every parser starts with.
  ParserLimits(
    maxLine: DefaultMaxLine,
    maxHeaderBytes: DefaultMaxHeaderBytes,
    maxHeaderCount: DefaultMaxHeaderCount,
    maxBody: DefaultMaxBody,
    maxChunkSize: DefaultMaxChunkSize)

proc noParserLimits*(): ParserLimits =
  ## The empty *override*: every field inherits. This is the base for building
  ## a partial policy — set the one field you care about and merge.
  ParserLimits(
    maxLine: LimitUnset, maxHeaderBytes: LimitUnset,
    maxHeaderCount: LimitUnset, maxBody: LimitUnset,
    maxChunkSize: LimitUnset)

proc unboundedParserLimits*(): ParserLimits =
  ## Every bound removed. Named so that a message with no limits is something
  ## a reader can see was chosen, and never something that happens by default.
  ParserLimits(
    maxLine: Unlimited, maxHeaderBytes: Unlimited,
    maxHeaderCount: Unlimited, maxBody: Unlimited,
    maxChunkSize: Unlimited)

proc merge*(base: ParserLimits; over: ParserLimits): ParserLimits =
  ## A field set in `over` wins; `LimitUnset` inherits. Note that `Unlimited`
  ## is a set value and does override — that is the point of keeping it
  ## distinct from unset.
  result = base
  if over.maxLine != LimitUnset: result.maxLine = over.maxLine
  if over.maxHeaderBytes != LimitUnset: result.maxHeaderBytes = over.maxHeaderBytes
  if over.maxHeaderCount != LimitUnset: result.maxHeaderCount = over.maxHeaderCount
  if over.maxBody != LimitUnset: result.maxBody = over.maxBody
  if over.maxChunkSize != LimitUnset: result.maxChunkSize = over.maxChunkSize

proc exceeds*(limit: int; value: int): bool =
  ## The one place the three states are interpreted. `Unlimited` and
  ## `LimitUnset` never trip; a positive limit trips when `value` passes it.
  limit > 0 and value > limit
