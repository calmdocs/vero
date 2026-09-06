# Linux example

A GTK4 interface for the Go worker in `../worker`: a progress bar and a restart
button on each row, and a footer showing what the worker is doing.

```bash
./build.sh
./main.py
```

`build.sh` builds `libvero.so` from `../../cshim`, then the worker. Both have to
be built on Linux: `-buildmode=c-shared` on a Mac produces a Mach-O dylib rather
than an ELF `.so`.

The app needs `python3-gi` and `gir1.2-gtk-4.0` installed.

## From a Mac

You do not need a Linux machine. `scripts/run-linux.sh` in the repository root
builds both pieces in a container, runs this app on a virtual display, and opens
it in the Screen Sharing app already on your Mac:

```bash
../../scripts/run-linux.sh
```

## What to look at

`main.py` talks to Go in three places. Nothing else in the file knows there is a
Go program involved:

- `Vero(library_path, worker_path)` starts and supervises the worker
- `run_in_thread(...)` delivers each event, marshalled onto the GTK main loop
  with `GLib.idle_add`
- `worker.call("restartJob", {"id": id})` calls the handler of that name. The
  reply is the new status, so the window redraws without waiting for the next
  event.
