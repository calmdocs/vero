# The worker

A Go program that pretends to sync three folders, so the three interface
examples have something real to drive. The same binary is behind all of them.

```bash
go build -o worker .
./worker            # on its own, logging to stderr
./worker -json      # the event stream on stdout
./worker -version
```

Two named handlers, which is what the interfaces call:

| Name | Takes | Returns |
|---|---|---|
| `status` | nothing | the current `Status` |
| `restartJob` | `{"id": 1}` | the new `Status` |

It pushes an event whenever its state changes, so nothing has to poll.
