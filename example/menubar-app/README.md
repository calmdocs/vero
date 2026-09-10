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

`Model.swift` is the whole interface to Go, and it is nothing but types. There
is no model class: `VeroModel` is the class every application used to write.

- `VeroModel<Status>` copies the worker out of the bundle when the copy on disk
  is missing or older, launches it, restarts it if it dies, keeps the last
  state it pushed in `vero.state`, and republishes the view when a new one
  arrives.
- `Status` is the one event type. The event channel carries no name, so a
  second type would be told apart only by whichever decode happened to
  succeed - widen this one instead.
- `StatusRequest` and `RestartJob` name the handler on the worker they are
  routed to and declare what comes back, so a call returns a `Status`.
- `vero.call(RestartJob(id:))` needs no reply handled: the worker pushes the
  new state, and that is what redraws.

`vero.worker` is the `VeroClient` underneath, for anything `VeroModel` does not
cover.

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
