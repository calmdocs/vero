# macOS example

A SwiftUI menu bar app driving the Go worker in `../worker`: live progress, a
restart button on each row, and an icon that changes between working and idle.

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

The README's example adds vero as a versioned package, and the archive arrives
with it - no `libvero.a`, no linker flags. This example does the opposite: a
path dependency on `../..` and `-L. -lvero`, with `build.sh` building the
archive first.

That is deliberate. A tagged release ships `CVero.xcframework` inside the
package, but a working tree has no release, so an example that built against
one would show you the last published vero rather than the checkout in front of
you. `scripts/run.sh` runs this example, and the screenshots come from it, so it
has to exercise the code as it is now - which is exactly how the changes in this
repository get caught before they are tagged.

So: an application follows the top-level README. This example does not, because
it is not an application.

## Shipping one

This example is a SwiftPM executable, not an application bundle, so the worker
sits beside the binary — vero looks there when `Bundle.main` has no resource by
that name. A real app carries it in `Contents/Resources` and links `libvero.a`
under "Link Binary With Libraries" in Xcode.

Build the archive universal, or the app will only run on one architecture. The
top-level README has the two `lipo` lines.
