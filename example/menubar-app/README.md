# macOS example

A SwiftUI menu bar app driving the Go worker in `../worker`.

```bash
./build.sh
./.build/debug/MenuBarExample
```

`build.sh` builds `libvero.a` from `../../cshim`, then the worker, then the app.
Look for the icon in the menu bar.

A menu bar panel closes whenever focus moves, which is awkward while you are
working on something else. For an ordinary window instead:

```bash
VERO_EXAMPLE_WINDOW=1 ./.build/debug/MenuBarExample
```

## What to look at

`Model.swift` is the whole interface to Go, and it is nothing but types:

- `VeroModel<Status>` launches the worker, restarts it if it dies, and
  republishes the view whenever the worker pushes a new `Status`
- `StatusRequest` and `RestartJob` name the handler on the worker they are
  routed to, and declare what comes back
- `vero.call(RestartJob(id:))` handles no reply: the worker pushes the new
  state, and that is what redraws

## Why this one builds the archive

Your own app adds vero as a versioned package and the C archive comes with it.
This example depends on the checkout at `../..` instead, which has no release to
take the archive from, so `build.sh` builds `libvero.a` first and the app links
it with `-L. -lvero`.

A real application also carries the worker in `Contents/Resources` and builds it
universal, or it runs on only one architecture. The top-level README has the
`lipo` lines.
