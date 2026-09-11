# macOS example

A SwiftUI menu bar app driving the Go worker in `../worker`.

```bash
./build.sh
./.build/debug/MenuBarExample
```

Look for the icon in the menu bar. A menu bar panel closes whenever focus
moves, so for an ordinary window instead:

```bash
VERO_EXAMPLE_WINDOW=1 ./.build/debug/MenuBarExample
```

`build.sh` builds `libvero.a` as well, because this example depends on the
checkout at `../..` rather than on a release, and only a release carries the
archive with it.
