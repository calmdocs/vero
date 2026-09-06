# How it fits together

There are three parts.

**The worker** is your logic: an ordinary Go program. It runs on its own as a
daemon, or an interface launches it. Same binary either way.

**The supervisor** launches the worker, restarts it if it dies, and carries
messages between the two. It is Go, embedded in your application as a C
archive, so the connection handling is written once rather than per platform.

**The interface** is native, and talks to the supervisor through nine C
functions. Each platform has a binding that wraps them: Swift for macOS, Python
for Linux, C# for Windows.

## The worker

```go
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

## The interface

```swift
@StateObject private var worker = try! VeroClient(
    bundledWorker: "myapp-worker", directoryName: "MyApp/bin")

worker.onEvent(Status.self) { status in
    self.jobs = status.jobs
}

Button("Restart") {
    worker.call(Restart(id: 3))
}
.disabled(worker.isBusy)
```

A request names the handler it is routed to and declares the type it comes back
as:

```swift
struct GetGroups: NamedRequest {
    static let name = "getGroups"
    typealias Reply = [Group]
}
```

`VeroClient` publishes `state`, `restarts`, `inFlight` and `isBusy` as
observable properties. `Vero`, underneath it, is the same client as a plain
async API, for when you are not using SwiftUI.

`VeroClient(bundledWorker:)` copies the worker out of the application bundle to
a writable directory before running it, and replaces the copy when the bundled
one is newer. A worker that updates itself cannot run from inside a signed
bundle.

## A crash in the worker does not close the interface

The worker is a separate process. A panic, or one of Go's unrecoverable
failures such as a concurrent map write, ends the worker only. The supervisor
reports it and starts another.

## The same binary runs headless

The worker does not know whether an interface launched it.

```
worker            a daemon; logs what changed, writes no stream
worker -json      the same, plus the event stream on stdout
worker -quiet     silent
```

## Why pipes

The interface and the worker use the standard input and output the operating
system created when the supervisor launched the worker.

- There is no filesystem object, so nothing else on the machine can connect to
  it.
- There is nothing left behind after a crash, no permissions to set and nothing
  to authenticate.
- When the application exits, for any reason, the worker's standard input closes
  and the worker exits with it. There is no PID file and no heartbeat.

The trade-off is that only the parent process can talk to the worker. If you
need several clients attached to one running worker, use a socket instead:
[keyexchange](https://github.com/calmdocs/keyexchange) and
[SwiftKeyExchange](https://github.com/calmdocs/SwiftKeyExchange) are the
calmdocs libraries for that.
