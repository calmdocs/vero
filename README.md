# vero

**Desktop applications whose logic is written once, in Go, and whose interface
is the platform's own toolkit.**

Every other way of building a desktop app in Go asks you to give something up.
Fyne and Gio draw their own widgets, so the result looks identical everywhere
and native nowhere. Wails and Lorca wrap a webview, which is Electron's
tradeoff in a smaller binary. Walk is Windows only.

vero takes the fourth path. The interface is genuinely SwiftUI, or WinUI, or
GTK — real controls, real menus, real notifications — and Go supplies
everything behind it.

<table>
<tr>
<td align="center" width="33%"><img src="docs/screenshots/macos.gif" width="100%"><br><sub><b>macOS</b> — SwiftUI, in the menu bar</sub></td>
<td align="center" width="33%"><img src="docs/screenshots/windows.gif" width="100%"><br><sub><b>Windows</b> — WPF</sub></td>
<td align="center" width="33%"><img src="docs/screenshots/linux.gif" width="100%"><br><sub><b>Linux</b> — GTK4</sub></td>
</tr>
</table>

All three are the same Go worker. Only the drawing differs — and all three are
recordings of the examples in this repository actually running: one on a Mac,
one on Windows 11 in a VM, and one under Xvfb in a container.

Everything you can see is a real control drawn by the platform. The icon on the
left of each row is a button, not a picture of one: it hovers, takes focus and
answers the keyboard the way a button on that platform does, because it *is*
one. Nothing is polling either — the progress moving is the worker pushing an
event each time its state changes.

```
   SwiftUI          WinUI            GTK
  ┌─────────┐    ┌─────────┐    ┌─────────┐
  │  macOS  │    │ Windows │    │  Linux  │   the platform's own controls
  └────┬────┘    └────┬────┘    └────┬────┘
       └──────────────┼──────────────┘
                 ┌────┴────┐
                 │ your Go │                 one implementation
                 └─────────┘
```

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

## Install

```bash
go get github.com/calmdocs/vero
```

```swift
.package(url: "https://github.com/calmdocs/vero", branch: "main")
```

## Building for all three platforms, from a Mac

Everything below was run on one Apple Silicon Mac: the universal macOS archive,
both Windows DLLs and both Linux shared libraries. No CI, no build farm, no
second machine.

It is this easy because of where the split falls. The **worker** is plain Go
with no cgo, so it cross-compiles to every target with the toolchain you already
have. Only the **shared library** needs a C compiler for the platform it will
run on, because that half is built by cgo.

Five scripts do all of it:

| | |
|---|---|
| `scripts/setup.sh` | installs whatever toolchain is missing, then builds everything |
| `scripts/run.sh` | opens the example on all three at once; `--iso win11.iso` the first time |
| `scripts/build-all.sh` | every artefact, for all three, into `dist/` |
| `scripts/release.sh` | packages a release: one archive per platform, named the way the bindings load them, plus checksums. `--publish` creates the GitHub release |
| `scripts/run-linux.sh` | the GTK example in a window on your Mac; `--record out.gif` to capture it |
| `scripts/run-windows.sh` | a Windows VM with your build on a disc; `--iso win11.iso --install` the first time |

`build-all.sh` skips any target whose toolchain is missing and names it. It also
works copied into your own project:

```bash
CSHIM=github.com/calmdocs/vero/cshim WORKER=./cmd/worker ./build-all.sh
```

The rest of this section is what these scripts do, for when you want to do it by
hand or change it.

### What you need

| For | Install |
|---|---|
| macOS | Xcode command line tools — `xcode-select --install` |
| Windows x64 | `brew install mingw-w64` |
| Windows ARM64 | [llvm-mingw](https://github.com/mstorsjo/llvm-mingw/releases) — unpack the `macos-universal` release into `~/toolchains/llvm-mingw`. Do **not** put its `bin` on your `PATH`: it ships its own `clang`, which shadows the system one and then cannot find the macOS SDK |
| Linux | `brew install colima docker && colima start` |
| The C# example | the [.NET SDK](https://dotnet.microsoft.com/download) — it builds WPF from macOS, given `-p:EnableWindowsTargeting=true` |

### The worker: every platform, no C toolchain at all

```bash
CGO_ENABLED=0 GOOS=darwin  GOARCH=arm64 go build -o worker-darwin-arm64 ./example/worker
CGO_ENABLED=0 GOOS=darwin  GOARCH=amd64 go build -o worker-darwin-amd64 ./example/worker
CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -o worker-amd64.exe    ./example/worker
CGO_ENABLED=0 GOOS=windows GOARCH=arm64 go build -o worker-arm64.exe    ./example/worker
CGO_ENABLED=0 GOOS=linux   GOARCH=amd64 go build -o worker-linux-amd64  ./example/worker
CGO_ENABLED=0 GOOS=linux   GOARCH=arm64 go build -o worker-linux-arm64  ./example/worker

# one universal binary for the Mac, rather than one per architecture
lipo -create worker-darwin-arm64 worker-darwin-amd64 -output worker
```

### macOS: a universal C archive

Swift links the archive statically, so it has to carry both architectures or the
app only runs on one of them.

```bash
export MACOSX_DEPLOYMENT_TARGET=11.0   # match the app, or the linker warns

CGO_ENABLED=1 GOARCH=arm64 \
    go build -buildmode=c-archive -o libvero-arm64.a ./cshim
CGO_ENABLED=1 GOARCH=amd64 CC="clang -arch x86_64 -mmacosx-version-min=11.0" \
    go build -buildmode=c-archive -o libvero-amd64.a ./cshim

lipo -create libvero-arm64.a libvero-amd64.a -output libvero.a
lipo -info libvero.a          # x86_64 arm64
```

One universal archive inside one universal app — you do not ship a binary per
architecture and choose between them at runtime.

Add `libvero.a` to your Xcode target under "Link Binary With Libraries" and add
the `Vero` package. `example/menubar-app/build.sh` does the same for SwiftPM.

### Windows: one DLL per architecture

Build for the architecture you will run on: an amd64 DLL under x64 emulation on
Windows-on-ARM does not work. See the caveat above.

```bash
CGO_ENABLED=1 GOOS=windows GOARCH=amd64 CC=x86_64-w64-mingw32-gcc \
    go build -buildmode=c-shared -o vero-amd64.dll ./cshim
CGO_ENABLED=1 GOOS=windows GOARCH=arm64 CC=aarch64-w64-mingw32-clang \
    go build -buildmode=c-shared -o vero-arm64.dll ./cshim

file vero-arm64.dll    # PE32+ executable (DLL) (console) Aarch64, for MS Windows
```

The C# example builds on the Mac too — WPF's targeting pack is just a NuGet
package, so only *running* it needs Windows:

```bash
cd example/wpf-app
dotnet publish -c Release -r win-arm64 --self-contained \
    -p:EnableWindowsTargeting=true -o out
cp ../../vero-arm64.dll  out/vero.dll
cp ../../worker-arm64.exe out/worker.exe
```

`vero.dll` is loaded by name and the worker is looked for beside the executable,
so both have to keep those names.

### Linux: a container, and only for the library

`-buildmode=c-shared` on macOS emits a Mach-O dylib, not an ELF `.so`. This is
the one piece that needs a Linux toolchain, and a container is the cheapest way
to have one:

```bash
colima start
mkdir -p out

docker run --rm -v "$PWD":/src:ro -v "$PWD/out":/out -w /src \
    -e GOCACHE=/tmp/gocache -e GOPATH=/tmp/go -e GOTOOLCHAIN=auto \
    golang:1.24-bookworm \
    sh -c 'CGO_ENABLED=1 go build -buildmode=c-shared -o /out/libvero.so ./cshim'

file out/libvero.so    # ELF 64-bit LSB shared object, ARM aarch64
```

Two things to know. colima shares only `$HOME`, so a bind mount from anywhere
under `/tmp` produces no files and no error — keep the output directory under
your home directory. And under `--platform linux/amd64` on an Apple Silicon Mac
the toolchain is emulated, where the Go compiler segfaults intermittently;
rerun it, and build the worker on the host.

Put `libvero.so` beside `main.py` — `bindings/python/vero.py` loads it from
there.

## Running them without the hardware

Building for three platforms is half of it. The examples also had to be *run*,
and recorded, and neither Linux nor Windows needed a second machine — both
recordings above were made on the Mac that built them.

`scripts/run-linux.sh` and `scripts/run-windows.sh` do what follows. Below is
what they are doing.

### Linux: Xvfb in a container

GTK wants an X display, so give it a virtual one. The image is Debian plus GTK4,
PyGObject, Xvfb and ImageMagick:

```dockerfile
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-gi gir1.2-gtk-4.0 libgtk-4-1 \
      xvfb x11vnc x11-utils imagemagick xauth ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
```

Start a display, run the example on it, photograph it twice a second:

```bash
docker build -t vero-gtk .
mkdir -p frames

docker run --rm -v "$PWD":/src -v "$PWD/frames":/frames \
    -w /src/example/gtk-app vero-gtk sh -c '
      Xvfb :99 -screen 0 480x440x24 &
      sleep 2
      export DISPLAY=:99
      python3 main.py &
      sleep 5
      xwininfo -root -children | grep vero        # "vero" 380x354+0+0
      for i in $(seq -w 1 20); do
          import -window root /frames/f$i.png
          sleep 0.5
      done'
```

No window manager is running, so the window sits at 0,0 with no decorations —
which is what you want for a screenshot. `xwininfo` gives you the geometry to
crop the frames to; anything that makes a GIF does the rest.

Mount the repository root, not just `example/gtk-app`: `main.py` reaches up to
`../../bindings/python` for the binding.

To watch it live rather than capture it, publish the port and run `x11vnc`
instead of the capture loop, then open it with the Screen Sharing app already on
your Mac:

```bash
docker run --rm -p 5901:5900 -v "$PWD":/src -w /src/example/gtk-app vero-gtk sh -c '
    Xvfb :99 -screen 0 480x440x24 &
    sleep 2
    export DISPLAY=:99
    python3 main.py &
    sleep 4
    x11vnc -display :99 -forever -nopw -listen 0.0.0.0'

open vnc://localhost:5901
```

### Windows: QEMU, driven through its monitor socket

Windows 11 on ARM in QEMU, with hardware virtualisation. Swap `-display none
-vnc 127.0.0.1:1` below for `-display cocoa` and it is an ordinary Mac window
you can click in; headless plus the QMP socket is what makes the session
scriptable, which is how the recording was made.

```bash
qemu-system-aarch64 \
    -machine virt,highmem=on -accel hvf -cpu host -smp 4 -m 6144 \
    -drive if=pflash,format=raw,readonly=on,file=$(brew --prefix)/share/qemu/edk2-aarch64-code.fd \
    -drive if=pflash,format=raw,file=vars.fd \
    -device qemu-xhci,id=usb \
    -drive if=none,id=cd0,format=raw,readonly=on,media=cdrom,file=windows.iso \
    -device usb-storage,drive=cd0,removable=true,bus=usb.0,bootindex=0 \
    -drive if=none,id=cd1,format=raw,readonly=on,media=cdrom,file=payload.iso \
    -device usb-storage,drive=cd1,removable=true,bus=usb.0,bootindex=2 \
    -drive if=none,id=hd0,format=qcow2,file=disk.qcow2 \
    -device nvme,drive=hd0,serial=winvm,bootindex=1 \
    -device ramfb -device usb-kbd -device usb-tablet \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
    -display none -vnc 127.0.0.1:1 \
    -qmp unix:/tmp/qmp.sock,server,nowait
```

Then everything is a QMP command on that socket — it speaks one JSON object per
line, and `qmp_capabilities` has to be the first:

```python
q.cmd("screendump", filename="/tmp/frames/f01.ppm")          # a screenshot
q.cmd("send-key", keys=[{"type": "qcode", "data": "ret"}])   # a keystroke
q.cmd("input-send-event", events=[                           # a click, 0..32767
    {"type": "abs", "data": {"axis": "x", "value": 27000}},
    {"type": "abs", "data": {"axis": "y", "value": 27000}},
    {"type": "btn", "data": {"down": True, "button": "left"}},
    {"type": "btn", "data": {"down": False, "button": "left"}}])
q.cmd("blockdev-change-medium", device="cd1",                # swap the CD
      filename="payload.iso", format="raw")
```

Five things to know:

- **Use `ramfb`, not `virtio-gpu`.** With virtio-gpu the firmware gives Windows
  a framebuffer nothing scans out: setup runs at 100% CPU behind a screen frozen
  on the vendor logo. `ramfb` is a plain linear framebuffer and works.
- **Keep the QMP socket path short.** Unix socket paths cap at 104 bytes, and
  QEMU refuses to start rather than truncating.
- **`blockdev-change-medium` is how you get builds in.** Make an ISO of the new
  binaries, swap it into the CD drive, copy them off inside the guest. No
  networking, no shares, no guest additions.
- **Keyboard layout is the guest's, not yours.** On a UK layout QEMU's
  `backslash` qcode types `#`; the real backslash is the `less` key.
- **Stop sending keys once the installer starts.** Windows media wants a
  keypress at "Press any key to boot from CD", so you send a burst; presses that
  outlive the prompt land in setup and activate whatever has focus.

The unattended answer file that gets Windows installed without a human is in
`.windows/unattend/`.

## The menu bar example

A SwiftUI menu bar app driving a Go worker: live progress, a Restart button,
and an icon that changes between working and idle.

```bash
cd example/menubar-app
./build.sh
./.build/debug/MenuBarExample
```

The same worker, with no interface at all:

```bash
./example/menubar-app/worker            # a daemon
./example/menubar-app/worker -json      # with the event stream
```

Two details the example gets right, both of which are easy to get wrong:

**It starts the worker from the app delegate, not from a view appearing.**
`MenuBarExtra` only builds its content when someone opens the menu, so starting
from `onAppear` means nothing happens until the first click — by which point
the icon is meant to have been showing progress.

**It draws with `latest` before waiting for `events`.** A window that has just
opened should show the current state, not an empty list waiting for something
to change.

## The GTK example

The same worker behind a GTK4 interface, for Linux:

```bash
cd example/gtk-app
./build.sh
./main.py            # needs python3-gi and gir1.2-gtk-4.0
```

Events arrive on their own thread, so it hands each one to GTK with
`GLib.idle_add` — the counterpart of the main-actor hop in the SwiftUI
example. Under WPF or WinUI that is `Dispatcher.InvokeAsync` or
`DispatcherQueue.TryEnqueue`.

## Tests

```bash
go test -race ./...
cd bindings/python && python3 -m unittest
swift build
```

The Go tests run the test binary as their own worker, so the worker really is
a separate process: crashes, restarts, concurrent requests and the lifecycle
are all exercised against a real one. The Python tests build the shared
library and the example worker and drive the whole stack through ctypes.

## Licence

MIT
