# macOS example

A SwiftUI menu bar app driving the Go worker in `../worker`.

```bash
./build.sh
./.build/debug/MenuBarExample
```

`build.sh` builds `libvero.a` from `../../cshim`, builds the worker, then builds
the app. Look for the icon in the menu bar.

A MenuBarExtra panel closes whenever focus moves, which makes it awkward to look
at while you are working on something else. For an ordinary window instead:

```bash
VERO_EXAMPLE_WINDOW=1 ./.build/debug/MenuBarExample
```

## What to look at

`Model.swift` is the whole interface to Go.

- `VeroClient` copies the worker out of the bundle when the copy on disk is
  missing or older, launches it, and restarts it if it dies.
- `StatusRequest` and `RestartJob` are types. Each names the handler on the
  worker it is routed to and declares what comes back, so a call returns a
  `Status`.
- Events arrive on the main actor, so they can go straight into published
  state.

## Why this example links the archive itself

Your own application adds vero as a versioned package, and the C archive comes
with it. This example instead uses a path dependency on `../..`, so it builds
against the checkout rather than the last published version. A checkout has no
release to take the archive from, so `build.sh` builds `libvero.a` first and the
app links it with `-L. -lvero`.

## Shipping a real app

This example is a SwiftPM executable rather than an application bundle, so the
worker sits beside the binary. Vero looks there when `Bundle.main` has no
resource by that name.

A real application instead:

- carries the worker in `Contents/Resources`
- adds the `Vero` package, which brings the C archive with it

Build the worker universal, or the app will only run on one architecture. The
top-level README has the two `lipo` lines.
