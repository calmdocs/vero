# Linux example

A GTK4 interface for the Go worker in `../worker`, drawn with real GTK widgets:
progress bars, a restart button on each row, and a footer that shows what the
worker is doing.

```bash
./build.sh
./main.py
```

`build.sh` builds `libvero.so` from `../../cshim` and the worker. Both have to
be built on Linux — `-buildmode=c-shared` on a Mac gives you a Mach-O dylib
rather than an ELF `.so`.

Needs `python3-gi` and `gir1.2-gtk-4.0`.

## From a Mac

You do not need a Linux machine. `scripts/run-linux.sh` in the repository root
builds both pieces in a container, runs this app on a virtual display, and opens
it in the Screen Sharing app already on your Mac:

```bash
../../scripts/run-linux.sh
```

## What to look at

`main.py` talks to Go in three places, and nothing else in the file knows there
is a Go program involved:

- `Vero(library_path, worker_path)` starts and supervises the worker
- `run_in_thread(...)` delivers each event, marshalled onto the GTK main loop
  with `GLib.idle_add`
- `worker.call("restartJob", {"id": id})` calls the handler of that name, and
  the reply is the new status, so the window redraws without waiting for the
  next event

A handler that returns an error arrives here as `Refused`, with the worker's own
message and the worker still running. That is different from `NotRunning`, and
the two deserve different responses.
