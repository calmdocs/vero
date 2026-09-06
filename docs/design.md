# How it fits together

## How it fits together

Your logic lives in a **worker**: an ordinary Go program. It runs on its own as
a daemon on a headless server, or an interface launches it — the same binary,
the same code, one flag between them.

A **supervisor** launches the worker, restarts it if it dies, and carries
messages. It is Go too, embedded in your application as a C archive, so every
platform gets the connection handling, retries and reconnection written once.

The **interface** is native, and talks to the supervisor through nine C
functions. That is the only part you write per platform, and it is thin.

```go
// the worker: your logic
w := vero.NewWorker(opts)
go work(w)

r := vero.NewRouter()
vero.Handle(r, "getGroups", func(ctx context.Context, _ struct{}) ([]Group, error) {
    return groups(), nil
})
vero.Handle(r, "addGroup", func(ctx context.Context, req AddGroup) (Group, error) {
    return add(req.Name)
})
w.Serve(r)
```

```swift
// the interface
@StateObject private var worker = try! VeroClient(
    bundledWorker: "myapp-worker", directoryName: "MyApp/bin")

worker.onEvent(Status.self) { status in
    self.jobs = status.jobs        // pushed the instant anything changes,
}                                  // already on the main actor

Button("Restart") {
    worker.call(Restart(id: 3)) {
        worker.call(GetJobs())     // after the first is answered
    }
}
.disabled(worker.isBusy)           // or worker.isBusy("restart")
```

A request declares the name it routes to and the type it comes back as:

```swift
struct GetGroups: NamedRequest {
    static let name = "getGroups"
    typealias Reply = [Group]
}
```

Without that a caller gets bytes and has to guess — try one type, then
another, until one decodes. An empty JSON array decodes as *every* list type,
so a list that happens to be empty is read as whatever was tried first, and the
bug only appears for the customer with no groups yet.

An application bundle is read-only and signed, so a worker that updates itself
cannot run from there. `VeroClient(bundledWorker:)` copies it somewhere
writable and decides on every launch whether the copy already there is newer
than the one just shipped — a decision with three ways to get it wrong, all of
which are quiet:

- **Compare versions, not contents.** A self-updated worker always differs from
  the bundled one, so copying on difference means the app copies its older
  worker over the newer one, the worker downloads the newer one again, and that
  repeats every launch — tens of megabytes at a time, silently.
- **Compare numerically.** As strings `0.10.0` sorts below `0.9.9`.
- **A universal binary is not a thin one.** `lipo` output begins `ca fe ba be`,
  which reads as `0xbebafeca` on a little-endian Mac; check only the big-endian
  spelling and the app rejects the worker it was built with.

`VeroClient` publishes `state`, `restarts`, `inFlight` and `isBusy`, so nothing
polls and nothing has to be wired up by hand. `Vero` underneath is the raw
async API for anything wanting a different shape.

It also retries **only** while the worker is not running. A refusal means the
worker got the request and said no, so sending it again just asks again — the
obvious retry loop, and the one applications write, turns one refusal into
five.

## Two things this gets you

**A crash in your worker logic does not kill the user interface.** The worker is a separate
process, so a panic — or one of Go's unrecoverable failures like a concurrent
map write, which `recover` cannot catch — kills the worker alone. The
supervisor reports it and starts another. Your menu stays on screen and can
say what happened.

**The same binary runs headless.** The worker has no idea whether an interface
launched it. Ship it on its own for servers, and the CLI is not a second
implementation of anything.

```
worker            a daemon; logs what changed, writes no stream
worker -json      the same, plus the event stream on stdout for anything watching
worker -quiet     silent
```

## Why pipes, and what that buys

The interface and the worker talk over the standard input and output the
operating system already created when the supervisor launched it.

That is not a smaller version of a socket, it is a different guarantee. There
is no filesystem object, so nothing else on the machine can connect — not
another user, not another process running as you, not anything on the network.
There is no socket to leave behind after a crash, no permissions to set, no
path length limit, and nothing to authenticate.

It also settles the lifecycle for free. **A worker cannot outlive the
interface that started it.** When the application quits, or crashes, or is
force quit, the worker's standard input closes and it exits. No PID file, no
heartbeat, no orphan.

The trade is that only the parent can talk to the worker. If you need several
clients attached to one running worker — a command line tool, a second app —
that needs a socket and everything a socket brings with it:
[keyexchange](https://github.com/calmdocs/keyexchange) and
[SwiftKeyExchange](https://github.com/calmdocs/SwiftKeyExchange) are the
calmdocs libraries for that arrangement.
