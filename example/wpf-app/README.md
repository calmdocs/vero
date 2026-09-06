# Windows example

The same worker and the same protocol as the macOS and Linux examples, drawn
with WPF.

On Windows:

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

Swap `arm64`/`win-arm64` for `amd64`/`win-x64` on an x64 machine, and use
`CC=x86_64-w64-mingw32-gcc` from `brew install mingw-w64`. `vero.dll` is loaded
by name and the worker is looked for beside the executable, so both keep those
names.

## Build for the architecture you will run on

A `windows/amd64` build of `vero.dll`, loaded into an x64 .NET process running
under emulation on Windows-on-ARM, does not work: the first call into Go either
never returns or takes the process down with `0xC0000409`, before anything is
printed. Built natively for `windows/arm64` the identical code is fine.

The plain Go worker is unaffected either way — it is only the shared library
that minds.

## What is verified

The binding, this example and the worker have been run end to end on Windows 11
on ARM: started, events, requests, restarts and shutdown. The recording in the
top-level README is this app running.
