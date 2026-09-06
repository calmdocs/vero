#!/bin/sh
# Installs everything needed to build vero for macOS, Windows and Linux on a
# Mac, then builds it.
#
#   ./scripts/setup.sh
#
# Safe to re-run: anything already present is left alone.
set -e

ROOT=$(cd "$(dirname "$0")" && pwd)/..
cd "$ROOT"
TOOLCHAINS=${TOOLCHAINS:-$HOME/toolchains}

command -v brew >/dev/null 2>&1 || {
    echo "Homebrew is needed: https://brew.sh" >&2; exit 1; }

echo "==> toolchains"
# Only what is actually missing.  Re-installing a working formula can leave it
# unlinked, and then the command it provides disappears from the PATH.
# Go is deliberately not in this list.  Installing a second one shadows
# whatever is already on the PATH, and the Go version decides the minimum macOS
# the archive supports - 1.27 stamps darwin/arm64 objects macOS 13, which
# silently drops macOS 12 users.  Bring your own.
command -v go >/dev/null 2>&1 || {
    echo "Go is missing: https://go.dev/dl - not installing one, because the" >&2
    echo "version decides the minimum macOS your build supports." >&2
    exit 1
}

for pair in x86_64-w64-mingw32-gcc:mingw-w64 colima:colima docker:docker \
            qemu-system-aarch64:qemu; do
    cmd=${pair%%:*}; formula=${pair#*:}
    command -v "$cmd" >/dev/null 2>&1 && continue
    echo "    installing $formula"
    brew install "$formula" >/dev/null 2>&1 || true
    command -v "$cmd" >/dev/null 2>&1 ||
        brew link --overwrite "$formula" >/dev/null 2>&1 || true
    command -v "$cmd" >/dev/null 2>&1 ||
        { echo "    $formula installed but $cmd is not on the PATH" >&2; }
done

# llvm-mingw is the only Windows-on-ARM cross compiler, and it is not in
# Homebrew, so take the latest release straight from GitHub.
if ! command -v aarch64-w64-mingw32-clang >/dev/null 2>&1 &&
   [ ! -x "$TOOLCHAINS/llvm-mingw/bin/aarch64-w64-mingw32-clang" ]; then
    echo "==> llvm-mingw (Windows ARM64 cross compiler)"
    URL=$(curl -fsSL https://api.github.com/repos/mstorsjo/llvm-mingw/releases/latest |
          sed -n 's/.*"browser_download_url": *"\(.*macos-universal.tar.xz\)".*/\1/p' | head -1)
    [ -n "$URL" ] || { echo "could not find the llvm-mingw download" >&2; exit 1; }
    mkdir -p "$TOOLCHAINS/llvm-mingw"
    curl -fsSL "$URL" | tar -xJ -C "$TOOLCHAINS/llvm-mingw" --strip-components=1
    echo "    installed in $TOOLCHAINS/llvm-mingw"
fi
# Deliberately not on PATH: llvm-mingw ships its own clang, which shadows the
# system one and then cannot find the macOS SDK.  The build scripts look in
# ~/toolchains/llvm-mingw and use it by full path, only for windows/arm64.

# colima can report "running" while the docker socket is not reachable.
docker info >/dev/null 2>&1 || { echo "==> starting colima"; colima start; }

echo "==> building"
exec "$ROOT/scripts/build-all.sh"
