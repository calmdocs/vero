#!/bin/sh
# Builds the shared library and the worker. Run from this directory.
set -e
cd "$(dirname "$0")"

echo "building libvero.so"
CGO_ENABLED=1 go build -buildmode=c-shared -o libvero.so ../../cshim

echo "building the worker"
go build -o worker ../worker

echo
echo "run it with:  ./main.py"
echo "needs:        python3-gi and gir1.2-gtk-4.0"
