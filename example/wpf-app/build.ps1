# Builds the Windows example. Run from this directory on Windows.
#
#   .\build.ps1
#   .\bin\Release\net8.0-windows\VeroExample.exe
#
# Needs the .NET 8 SDK and Go with cgo. On Windows that means a gcc:
# either TDM-GCC or the mingw-w64 that ships with msys2.
$ErrorActionPreference = "Stop"

Write-Host "building vero.dll"
$env:CGO_ENABLED = "1"
go build -buildmode=c-shared -o vero.dll ../../cshim

Write-Host "building the worker"
go build -o worker.exe ../worker

Write-Host "building the app"
dotnet build -c Release

# vero.dll is loaded by name, so it has to sit beside the executable, and the
# worker with it: vero looks there when there is no application bundle.
$out = "bin\Release\net8.0-windows"
Copy-Item vero.dll, worker.exe $out -Force

Write-Host ""
Write-Host "run it with:  .\$out\VeroExample.exe"
