# The protocol

## The wire format

Newline delimited JSON, both ways. Your own message travels in `p`, untouched:

```jsonc
// to the worker
{"id": 7, "p": <your request>}

// from the worker
{"t": "reply", "id": 7, "p": <your reply>}
{"t": "reply", "id": 7, "e": "no job with id 99"}
{"t": "event", "p": <your event>}
```

Replies are matched to requests by id, so a slow request does not hold up the
events behind it, and the worker answers requests concurrently.

Standard output carries this stream and nothing else. `NewWorker` takes the real
stdout for the protocol and points the package-level `os.Stdout` at stderr, so
`fmt.Println` anywhere in your program writes to stderr instead.

Call `NewWorker` before starting any goroutine: it reassigns a package-level
variable, so printing concurrently with it is a data race.

## Errors

A handler returns `(reply, error)`. Returning an error sends the message to the
interface; the worker keeps running.

```go
return nil, fmt.Errorf("no job with id %d", id)
```

The interface receives one of two errors:

```swift
catch VeroError.refused(let message)     // the worker received it and returned an error
catch VeroError.notRunning               // the worker is starting or restarting
```

## One worker at a time

Two copies of the same application - one in `/Applications`, one still in
`~/Downloads` - are two processes with the same bundle identifier, and macOS
runs both. Each would start a worker, and both would write to the same state.

A `Supervisor` takes an exclusive lock before starting anything, keyed by
default on the worker's path:

```go
s := vero.Supervise(vero.SupervisorOptions{Path: worker})
if errors.Is(s.Err(), vero.ErrAlreadyRunning) {
    // another copy is already running
}
```

Requests to a supervisor that did not get the lock return `ErrAlreadyRunning`,
not `ErrWorkerNotRunning`. The bindings raise `alreadyRunning` in Swift,
`AlreadyRunning` in Python and `AlreadyRunningException` in C#.

The lock is an open file - `flock` on Unix, `LockFileEx` on Windows - so the
operating system releases it when the process exits, including after a crash.

`Lock` sets the key, for two applications that share a worker binary and should
both be allowed to run. `NoLock` turns the lock off.

## Platform support

Each platform has one binding over the same nine C functions.

| | Binding | Example |
|---|---|---|
| **macOS** | `Sources/Vero` (Swift) | `example/menubar-app` |
| **Linux** | `bindings/python` | `example/gtk-app` |
| **Windows** | `bindings/csharp` | `example/wpf-app` |

All three are tested against a real worker: startup, events, requests, errors,
restarts and shutdown. All three can call a named handler registered with
`vero.Handle` - `call` in Swift and Python, `CallAsync` in C#.

The Go side is the same everywhere. The worker is pure Go with no cgo.

```
linux/amd64     ELF 64-bit LSB executable, x86-64
windows/amd64   PE32+ executable (console) x86-64
windows/arm64   PE32+ executable (console) Aarch64
darwin/arm64    Mach-O 64-bit executable arm64
```

## Build the library for the architecture you will run on

A `windows/amd64` DLL loaded into an x64 .NET process, running under emulation
on Windows-on-ARM, does not work: the first call into Go either does not return
or ends the process with `0xC0000409`. Built for `windows/arm64` the same code
runs correctly.

The worker is not affected. This applies only to the shared library.

## Which build of the library

Swift links the archive statically. Python and C# load a shared library at
runtime.

```bash
go build -buildmode=c-archive -o libvero.a   ./cshim   # Swift
go build -buildmode=c-shared  -o libvero.so  ./cshim   # Python, Linux
go build -buildmode=c-shared  -o vero.dll    ./cshim   # C#, Windows
```

A tagged release ships the archive inside the Swift package, so a macOS
application does not build one. [Building and running from a
Mac](building.md) has the cross-compilation commands for the other two.
