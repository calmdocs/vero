# How the backend and frontend communicate

The Go backend (the **worker**) runs as a separate child process of the app.
It talks to the frontend over that process's **standard input, output and error
pipes**, sending **newline-delimited JSON**. There's no socket, no localhost
port, no HTTP and no named pipe.

Between the GUI and the worker sits [`cshim`](../cshim/main.go), a small Go
library that the frontend links in. It launches the worker, restarts it if it
crashes, and handles the protocol, so the Swift, C# and Python code only makes
plain C function calls.

```
SwiftUI / WPF / GTK app
   │  C calls (VeroStart, VeroCall, VeroWaitForEvent, …)
   ▼
libvero (cshim/main.go → vero.Supervisor)      ← Go, runs inside the app process
   │  stdin:  requests, one JSON object per line
   │  stdout: replies and state events, one per line
   │  stderr: human-readable logs
   ▼
worker binary (your main.go → vero.Worker)     ← Go, separate process
```

## What kind of pipes

They are ordinary anonymous OS pipes, created by Go's `os/exec` in
`Supervisor.runOnce` ([supervisor.go](../supervisor.go)):

```go
cmd := exec.Command(s.opts.Path, s.opts.Args...)
stdin, _  := cmd.StdinPipe()   // frontend → worker: requests
stdout, _ := cmd.StdoutPipe()  // worker → frontend: replies + state events
stderr, _ := cmd.StderrPipe()  // worker → frontend: log lines
cmd.Start()
```

Each call asks the OS for a pipe, which is a one-way kernel buffer with a read
end and a write end. The child gets one end as its standard input, output or
error, and the supervisor keeps the other.

- **macOS and Linux:** real Unix pipes, created with `pipe(2)` (on Linux,
  `pipe2` with `O_CLOEXEC`). This is the same mechanism as
  `worker | somethingelse` in a shell.
- **Windows:** Go calls Win32 `CreatePipe`, which makes an anonymous pipe. The
  child inherits the handle as its standard input, output or error. Internally
  Windows builds anonymous pipes on its named-pipe system with a unique hidden
  name, but neither side ever uses or sees a name.

vero has no platform-specific pipe code; Go's `os/exec` hides the difference.
The only Windows-specific part of spawning is
[spawn_windows.go](../spawn_windows.go), which stops a console window from
appearing next to the app.

These are **not** Unix domain sockets (`AF_UNIX`). There's no socket file on
disk and nothing to connect to. The pipes are one-way and unnamed, which is why
vero uses three of them.

The worker doesn't open anything itself. It reads `os.Stdin` and writes the
real `os.Stdout`, just as a command-line program would.

## The wire format: one `Envelope` per line

A pipe is just a stream of bytes, so vero needs a way to mark where one message
ends. Every message is one JSON object on one line: `json.Encoder.Encode` adds
the newline, and a `bufio.Scanner` on the other side splits the stream on
newlines. A mutex in the worker makes sure two goroutines can't mix their
output on one line. Each line can be at most 16 MiB (`MaxLineSize`).

The line is an `Envelope`, defined in [vero.go](../vero.go):

```go
type Envelope struct {
    Kind    string          `json:"t,omitempty"` // "event" | "reply" (empty on requests)
    ID      uint64          `json:"id,omitempty"` // matches a reply to its request
    Name    string          `json:"n,omitempty"`  // handler name, e.g. "restartJob"
    Payload json.RawMessage `json:"p,omitempty"`  // your own message, untouched
    Error   string          `json:"e,omitempty"`  // set instead of p when a handler fails
}
```

The handler name travels in the envelope, not inside your payload, so vero can
route a request without knowing anything about your message types.

## Frontend → worker: requests

- `Supervisor.Call` ([supervisor.go](../supervisor.go)) gives each request an
  increasing `id` and records it in a `pending` map. It then writes
  `{"id":N,"n":"restartJob","p":{...}}` to the worker's stdin and waits for the
  reply with that `id`, until the context is cancelled or the supervisor stops.
- On the worker side, `serveEnvelopes` ([worker.go](../worker.go)) scans stdin
  line by line and runs each request in its own goroutine. That way a slow
  handler doesn't hold up other requests or events. The router
  ([router.go](../router.go)) looks up the handler by name and decodes the
  payload into that handler's own request type. You register handlers with
  `vero.Handle`, `vero.Update` or `vero.UpdateWith`.
- The handler's result goes back as `{"t":"reply","id":N,"p":...}`. If the
  handler returns an error, the reply carries `"e":"..."` instead. The frontend
  receives that as a `RemoteError`, which is different from
  `ErrWorkerNotRunning`. A panic in a handler only fails that one request.

## Worker → frontend: state is pushed, not polled

- `vero.NewState` ([state.go](../state.go)) registers one state struct, and
  every change goes through `state.Do`.
- `emitState` ([worker.go](../worker.go)) encodes the state to JSON every
  100 ms (`DefaultStateInterval`). It sends `{"t":"event","p":<state>}` only
  when the bytes differ from the last event sent, so nothing goes over the pipe
  while nothing changes.
- `vero.Update` handlers also send the new state back as their reply. The
  frontend therefore never draws a state from before its own change.
- On the frontend side, `readEvents` ([supervisor.go](../supervisor.go)) splits
  stdout lines into events and replies. Events update `latest` and trigger
  `OnEvent`. Replies go to whichever caller is waiting on that `id`.

This is why the Restart button in the README example ignores the reply: the
pushed state is what redraws the row.

## Protecting stdout

In serve mode, `NewWorker` ([worker.go](../worker.go)) keeps the real stdout
for the protocol and points `os.Stdout` at stderr. A stray `fmt.Println`
anywhere in the program, including in dependencies, then lands on stderr
instead of corrupting a message. `w.Log` writes to stderr, and the supervisor
passes those lines on through `OnLog`.

The supervisor sets `VERO_SERVE=1` in the worker's environment, which is how
the worker knows a frontend is driving it. The same binary also runs
standalone, with `-json` to print its events to a terminal.

## Lifecycle

- **Shutdown:** the supervisor closes the worker's stdin. The worker's read
  hits EOF, so it cancels its context, waits up to `ShutdownGrace` (5 s) for
  handlers, and exits. If the worker is still running 3 s after stdin closes,
  the supervisor kills it.
- **Frontend dies:** the OS closes the frontend's end of the pipe, so the
  worker sees EOF on stdin and exits the same way.
- **Worker dies:** the supervisor's read of stdout hits EOF. It fails any
  requests still waiting for a reply and restarts the worker with exponential
  backoff (200 ms, doubling up to 30 s). Once a worker has run for 30 s, the
  backoff resets.
- A file lock ([lock.go](../lock.go)) makes sure only one app process
  supervises a given worker at a time.

## Why pipes rather than a local server

- **Private:** only the parent process holds the other ends. No port is open
  that another program on the machine could connect to, and there's nothing to
  authenticate.
- **Shutdown and crashes are signalled automatically:** EOF on either side
  means the other has gone. No heartbeat or timeout logic is needed.
- **Nothing to configure:** there are no port clashes, firewall prompts or
  leftover socket files, and it works the same on macOS, Windows and Linux.
- **Easy to debug:** run the worker by hand with `-json` and read the event
  stream in a terminal. With `VERO_SERVE=1` set, you can also type requests
  into it.

The downside is that a pipe has a single reader, so only the one process that
launched the worker can talk to it. A second app or a browser can't attach to
the same worker the way it could with a localhost server.

## The C boundary to each native UI

[cshim/main.go](../cshim/main.go) is built with `-buildmode=c-archive` and
exports `VeroStart`, `VeroCall`, `VeroRequest`, `VeroLatest`,
`VeroWaitForEvent`, `VeroState`, `VeroRestarts`, `VeroStop` and `VeroFree`.
Each function that returns a string returns a JSON envelope, `{"p":...}` or
`{"e":"..."}`, which the caller must release with `VeroFree`.

- **Swift:** [CVero.h](../Sources/CVero/include/CVero.h), wrapped by
  `VeroClient` and `VeroModel`. `vero.call(RestartJob(id:))` sends the request;
  `vero.state` is updated from the pushed events.
- **C#:** [Vero.cs](../bindings/csharp/Vero.cs), via `[DllImport]`.
- **Python/GTK:** [vero.py](../bindings/python/vero.py), via `ctypes.CDLL`. A
  background thread blocks on `VeroWaitForEvent`, which works because `CDLL`
  releases the Python interpreter lock during the call.
