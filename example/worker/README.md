# The worker

A Go program that pretends to sync three folders, so the three interface
examples have something real to drive. It is the same binary behind all of
them.

```bash
go build -o worker .
./worker            # on its own, logging to stderr
./worker -json      # the event stream on stdout, for piping somewhere
./worker -version
```

Two named handlers, which is what the interfaces call:

| Name | Takes | Returns |
|---|---|---|
| `status` | nothing | the current `Status` |
| `restartJob` | `{"id": 1}` | the new `Status` |

and an event pushed whenever the state changes, so nothing polls.

Run on its own it never returns. Run by an interface it answers requests until
that interface quits, then exits when its standard input closes.

`r.Fallback` is also wired to an older handler that switches on a `"type"` field
in the request, so an interface that does not use named handlers still works.
`r.FallbackCalls()` counts how many requests have taken that path.
