# C# binding

The Windows equivalent of `Sources/Vero`: a thin layer over the same nine C
functions.

```powershell
go build -buildmode=c-shared -o vero.dll .\cshim
go build -o worker.exe .\your\worker
```

Put `vero.dll` beside your executable and add `Vero.cs` to your project. The
worker is looked for beside the executable too.

```csharp
using var vero = new VeroClient("worker.exe");

// Pushed whenever the worker's state changes. Nothing polls.
await foreach (JsonElement status in vero.Events())
{
    // Dispatcher.Invoke(...) before touching a control
}

// Calls the handler registered as "restartJob" with vero.Handle over in Go.
var status = await vero.CallAsync<object, Status>("restartJob", new { id = 3 });
```

`SendAsync` is the same thing without a name, for a worker that routes on
something inside the request instead.

A handler that returns an error arrives as `RefusedException`, carrying the
worker's own message, with the worker still running — which is different from
`NotRunningException` and usually wants a different response.

## Build for the architecture you will run on

A `windows/amd64` DLL loaded into an x64 .NET process running under emulation on
Windows-on-ARM does not work: the first call into Go either does not return, or
ends the process with `0xC0000409`. Built for `windows/arm64` the same code runs
correctly. The pure-Go worker is unaffected; it is only the shared library.

From a Mac, `aarch64-w64-mingw32-clang` from
[llvm-mingw](https://github.com/mstorsjo/llvm-mingw) builds the ARM64 DLL, and
`dotnet publish -r win-arm64 -p:EnableWindowsTargeting=true` builds the app.
`scripts/run-windows.sh` does both and boots a VM with the result.
