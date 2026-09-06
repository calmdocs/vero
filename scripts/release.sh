#!/bin/sh
# Builds a release: the library and the worker, for every platform, packaged
# so nobody downloading them needs a cross toolchain of their own.
#
#   ./scripts/release.sh v0.2.0
#   ./scripts/release.sh v0.2.0 --publish     # also create the GitHub release
#
# Everything lands in dist/release/.  Linux is built for both architectures,
# which takes a few minutes: one of them runs emulated.
set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

VERSION=${1:?usage: scripts/release.sh <version> [--publish]}
PUBLISH=no
[ "$2" = "--publish" ] && PUBLISH=yes
case "$VERSION" in
    v*) ;;
    *) echo "version should look like v0.2.0" >&2; exit 2 ;;
esac

OUT="$ROOT/dist/release"
rm -rf "$OUT"; mkdir -p "$OUT"

echo "==> building everything"
ALL_ARCHES=1 "$ROOT/scripts/build-all.sh" >/dev/null

DIST="$ROOT/dist"
missing=""
need() { [ -f "$DIST/$1" ] || missing="$missing $1"; }
need libvero.a
need vero-amd64.dll
need vero-arm64.dll
need libvero-amd64.so
need libvero-arm64.so
need worker-macos-universal
[ -n "$missing" ] && { echo "not releasing, these did not build:$missing" >&2; exit 1; }

echo "==> packaging"
# The names inside an archive are the names the bindings load: vero.dll,
# libvero.so, libvero.a, worker.  Nobody should have to rename anything.
stage() {
    name=$1; shift
    dir="$OUT/$name"; rm -rf "$dir"; mkdir -p "$dir"
    while [ $# -gt 0 ]; do
        cp "$DIST/$1" "$dir/$2"
        shift 2
    done
    [ -f "$DIST/vero.h" ] && cp "$DIST/vero.h" "$dir/vero.h"
    cp "$ROOT/LICENSE" "$dir/" 2>/dev/null || true
    cat > "$dir/README.txt" <<TXT
vero $VERSION - $name

Put these two beside the executable that loads them:

  the library  linked or loaded by name (libvero.a, vero.dll, libvero.so)
  worker       launched by the library at runtime

vero.h declares the nine C functions, for calling them from C or C++ directly.
The Swift, C# and Python bindings do not need it.

  https://github.com/calmdocs/vero
TXT
}

archive() {
    name=$1; format=$2
    ( cd "$OUT" &&
      if [ "$format" = zip ]; then zip -qr "$name.zip" "$name"; else tar -czf "$name.tar.gz" "$name"; fi )
    rm -rf "$OUT/$name"
    echo "  $name.$format"
}

n="vero-$VERSION-darwin-universal"
stage "$n" libvero.a libvero.a worker-macos-universal worker
archive "$n" tar.gz

n="vero-$VERSION-windows-amd64"
stage "$n" vero-amd64.dll vero.dll worker-windows-amd64.exe worker.exe
archive "$n" zip

n="vero-$VERSION-windows-arm64"
stage "$n" vero-arm64.dll vero.dll worker-windows-arm64.exe worker.exe
archive "$n" zip

n="vero-$VERSION-linux-amd64"
stage "$n" libvero-amd64.so libvero.so worker-linux-amd64 worker
archive "$n" tar.gz

n="vero-$VERSION-linux-arm64"
stage "$n" libvero-arm64.so libvero.so worker-linux-arm64 worker
archive "$n" tar.gz

( cd "$OUT" && shasum -a 256 ./* > SHA256SUMS && echo "  SHA256SUMS" )

echo
ls -lh "$OUT" | awk 'NR>1 {print "  "$9"  "$5}'

if [ "$PUBLISH" = yes ]; then
    command -v gh >/dev/null 2>&1 || { echo "gh is not installed" >&2; exit 1; }
    echo
    echo "==> creating the GitHub release $VERSION"
    gh release create "$VERSION" "$OUT"/* --title "$VERSION" --generate-notes
else
    echo
    echo "not published. To do that:  ./scripts/release.sh $VERSION --publish"
fi
