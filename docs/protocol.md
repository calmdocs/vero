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

Replies are matched to requests by id, so a slow request never holds up the
events behind it, and the worker answers requests concurrently.

**Standard output carries this stream and nothing else**, and you do not have to
police that. `NewWorker` takes the real stdout for the protocol and points the
package-level `os.Stdout` at stderr, so every `fmt.Println` in your program —
including ones inside dependencies you cannot edit, and ones somebody adds next
year — lands harmlessly on stderr. There is nothing to audit.

The one requirement is to call `NewWorker` before starting any goroutine, since
it reassigns a package-level variable. Anything printing concurrently with that
is a data race, and the race detector will say so.

## One worker at a time

Two copies of an application - the one in `/Applications` and the one still in
`~/Downloads` after an update - are two processes with the same bundle
identifier, and macOS will run both. Without something stopping it, each starts
a worker and both work on the same state. One window too many is a nuisance;
two workers is corruption.

So a `Supervisor` takes an exclusive lock before it starts anything, keyed by
default on the worker's path:

```go
s := vero.Supervise(vero.SupervisorOptions{Path: worker})
if errors.Is(s.Err(), vero.ErrAlreadyRunning) {
    // offer to switch to the copy that is running
}
```

Requests to a supervisor that never got the lock return `ErrAlreadyRunning`
rather than `ErrWorkerNotRunning`, because the two want different responses:
one is worth waiting out, the other never resolves. The bindings raise
`alreadyRunning` in Swift, `AlreadyRunning` in Python and
`AlreadyRunningException` in C#.

The lock is held by an open file - `flock` on Unix, `LockFileEx` on Windows -
so the operating system drops it when the process does, crash included. There
is no stale lock to clear by hand.

`Lock` sets the key, for two applications that share a worker binary and should
still both run. `NoLock` turns it off.

## Errors

A handler returns `(reply, error)`. Return an error and the interface gets the
message, not a dropped connection:

```go
return nil, fmt.Errorf("no job with id %d", id)
```

```swift
catch VeroError.refused(let message)     // the worker got it and said no
catch VeroError.notRunning               // the worker is starting or restarting
```

That distinction matters more than it looks. *The worker refused this* should
show the message and carry on; *the worker is not running* should wait. An
interface that treats them the same is wrong half the time.

## Platform support

Each platform needs one thin binding over the same nine C functions. All
three exist.

| | Binding | Example | State |
|---|---|---|---|
| **macOS** | `Sources/Vero` (Swift) | `example/menubar-app` | tested and running |
| **Linux** | `bindings/python` | `example/gtk-app` | tested and running |
| **Windows** | `bindings/csharp` | `example/wpf-app` | tested and running |

The Go side is identical everywhere: pipes and `os/exec` need no
platform-specific code, and the worker is pure Go with no cgo at all.

```
linux/amd64     ELF 64-bit LSB executable, x86-64
windows/amd64   PE32+ executable (console) x86-64
windows/arm64   PE32+ executable (console) Aarch64
darwin/arm64    Mach-O 64-bit executable arm64
```

**All three bindings are verified end to end** against a real worker — started,
events, requests, refusals, restarts and shutdown — and they behave identically,
because they parse the same envelopes from the same nine functions. All three
can also call a named handler registered with `vero.Handle`: `call` in Swift and
Python, `CallAsync` in C#.

One caveat on Windows: **build the library for the architecture you will run
on.** The `windows/amd64` DLL, loaded into an x64 .NET process running under
emulation on Windows-on-ARM, either hangs inside the first call or ends the
process with `0xC0000409`. Built for `windows/arm64` — Go with
`CC=aarch64-w64-mingw32-clang` from llvm-mingw, and `dotnet publish
-r win-arm64` — the same code runs correctly, and that is what the recording
above is. The pure-Go worker is unaffected; it is only the shared library.

### Which build of the library

Swift links the archive statically; Python and C# load a shared library at
runtime instead:

```bash
go build -buildmode=c-archive -o libvero.a   ./cshim   # Swift
go build -buildmode=c-shared  -o libvero.so  ./cshim   # Python, Linux
go build -buildmode=c-shared  -o vero.dll    ./cshim   # C#, Windows
```

Those are the plain forms. [Building for all three platforms, from a
Mac](#building-for-all-three-platforms-from-a-mac) below has the real ones,
with the cross toolchains and the architectures spelled out.
