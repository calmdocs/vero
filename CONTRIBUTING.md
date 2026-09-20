# Contributing

Everything here runs on a Mac with Go and Xcode installed.

## The tests

Three suites, none of which needs a Windows or Linux machine:

```bash
go test -race ./...                             # the worker, the router, the lock
cd bindings/python && python3 -m unittest       # the Python binding, end to end
swift build                                     # the Swift package compiles
```

The Go tests take about half a minute, because several of them start a real
worker process and wait on it.

The Python tests build the shared library and the example worker first, then
drive them through ctypes, so what they exercise is the whole stack rather than
the binding on its own. That means they need a working cgo toolchain, and they
take a few seconds longer than they look like they should.

There is no Swift test target: `swift build` is there to catch a package that
no longer compiles.

Before sending a change, `gofmt -l .` should print nothing and `go vet ./...`
should be quiet.

## Building for every platform

`scripts/build-all.sh` builds macOS, Windows and Linux into `dist/`, skipping
any target whose toolchain is missing rather than failing the run.
`scripts/setup.sh` installs those toolchains, and `scripts/run.sh` opens the
three examples at once - macOS natively, Linux in a container over VNC, and
Windows in a VM.

The three example apps are [example/menubar-app](example/menubar-app),
[example/wpf-app](example/wpf-app) and [example/gtk-app](example/gtk-app), all
driving the same worker in [example/worker](example/worker).
