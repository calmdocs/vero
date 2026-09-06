# Windows example

A WPF interface for the Go worker in `../worker`. Same worker and same protocol
as the macOS and Linux examples.

To build and run it on Windows:

```powershell
.\build.ps1
.\bin\Release\net8.0-windows\VeroExample.exe
```

## Building it from a Mac

You do not need Windows to build this, only to run it. WPF's targeting pack is
a NuGet package, so the .NET SDK on macOS will produce a Windows application:

```bash
# the library, for the architecture you will run on
CGO_ENABLED=1 GOOS=windows GOARCH=arm64 CC=aarch64-w64-mingw32-clang \
    go build -buildmode=c-shared -o vero.dll ../../cshim
CGO_ENABLED=0 GOOS=windows GOARCH=arm64 go build -o worker.exe ../worker

# the app
dotnet publish -c Release -r win-arm64 --self-contained \
    -p:EnableWindowsTargeting=true -o out
cp vero.dll worker.exe out/
```

On an x64 machine, swap `arm64` for `amd64` and `win-arm64` for `win-x64`, and
use `CC=x86_64-w64-mingw32-gcc` from `brew install mingw-w64`.

Keep both file names. `vero.dll` is loaded by name, and the worker is looked for
beside the executable.

To run it from the Mac, `scripts/run-windows.sh` in the repository root builds
this app, puts it on a disc image and boots a Windows VM with it:

```bash
../../scripts/run-windows.sh
```

## Build the library for the architecture you will run on

A `windows/amd64` build of `vero.dll`, loaded into an x64 .NET process running
under emulation on Windows-on-ARM, does not work: the first call into Go either
never returns or ends the process with `0xC0000409`. Built for `windows/arm64`
the same code runs correctly.

This applies only to the shared library. The plain Go worker is unaffected.
