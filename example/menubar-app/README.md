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

`Model.swift` is the whole interface to Go, and it is short. `VeroClient` copies
the worker out of the bundle when the copy on disk is missing or older, launches
it, supervises it, and restarts it if it dies — none of which is in this
example, because none of it should be.

The requests are types: `StatusRequest` and `RestartJob` each name the handler
on the worker they are routed to and declare what comes back, so the call site
gets a `Status` rather than bytes to guess at.

Events arrive already on the main actor, so they can go straight into published
state.

## Why this links the archive itself

An application adds vero as a versioned package, and the archive comes with it.
This example uses a path dependency on `../..` instead, and links the archive
itself with `-L. -lvero`, which is why `build.sh` builds `libvero.a` first.

A tagged release ships the archive inside the package; a working tree has no
release. Using a path dependency means this example builds against the checkout
rather than the last published version.

## Shipping one

This example is a SwiftPM executable, not an application bundle, so the worker
sits beside the binary — vero looks there when `Bundle.main` has no resource by
that name. A real app carries it in `Contents/Resources` and links `libvero.a`
under "Link Binary With Libraries" in Xcode.

Build the archive universal, or the app will only run on one architecture. The
top-level README has the two `lipo` lines.
