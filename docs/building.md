# Building and running, from a Mac

Everything here is what `scripts/setup.sh`, `scripts/run.sh` and
`scripts/release.sh` do, for when you want to do it by hand or change it.

## Building for all three platforms, from a Mac

The **worker** is plain Go with no cgo, so it cross-compiles to every target
with the toolchain you already have. Only the **shared library** needs a C
compiler for the platform it will run on, because that half is built by cgo.

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

You only need this to work on vero itself, or to build from an unreleased
commit. A tagged version ships the archive inside the Swift package as an
XCFramework, so an application that depends on a version links it without
building anything - see the README.

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

Building it by hand like this, add `libvero.a` to your Xcode target under "Link
Binary With Libraries" alongside the `Vero` package. `example/menubar-app` does
the same for SwiftPM, with `-L. -lvero`, because it builds against the checkout
rather than a release.

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
