#!/bin/sh
# Builds the Go archive, then the app. Run from this directory.
set -e
cd "$(dirname "$0")"

echo "building libvero.a"
CGO_ENABLED=1 go build -buildmode=c-archive -o libvero.a ../../cshim

echo "building the worker"
go build -o worker ../worker

echo "building the app"
swift build

# A SwiftPM executable is not an application bundle, so there is nothing to
# embed the worker in. vero looks beside the executable when Bundle.main has
# no resource by that name, which is what makes swift build usable during
# development; a real .app would carry it in Contents/Resources.
cp worker .build/debug/worker

echo
echo "run it with:  ./.build/debug/MenuBarExample"
