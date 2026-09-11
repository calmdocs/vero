# Windows example

A WPF interface for the Go worker in `../worker`. Same worker and same protocol
as the macOS and Linux examples.

On Windows:

```powershell
.\build.ps1
.\bin\Release\net8.0-windows\VeroExample.exe
```

From a Mac, without a Windows machine. This builds it, puts it on a disc image
and boots a Windows VM with it:

```bash
../../scripts/run-windows.sh
```
