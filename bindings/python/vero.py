"""Drive a Go worker from a Python interface - GTK, Qt, or anything else.

This is the Linux equivalent of Sources/Vero: a thin layer over the same seven
C functions, with no logic of its own.  Supervision, restarts, framing and
reconnection all happen in Go, on the other side of the boundary.

Build the shared library once.  It is the same library for every application,
because the worker's path arrives at runtime and every message is JSON:

    go build -buildmode=c-shared -o libvero.so ./cshim
    go build -o worker ./your/worker

Then:

    from vero import Vero

    v = Vero("./libvero.so", "./worker")
    for status in v.events():
        print(status["jobs"])

Every string the library returns was allocated by Go with malloc, so each one
is handed back to VeroFree here.  Nothing else frees it.
"""

from __future__ import annotations

import ctypes
import json
import threading
from typing import Any, Iterator


class VeroError(Exception):
    """Something went wrong talking to the worker."""


class Refused(VeroError):
    """The worker received the request and refused it.

    It is still running, so this is a problem with the request.  Show the
    message and carry on.
    """


class AlreadyRunning(VeroError):
    """Another process is already running a worker for this application.

    Offer to switch to the copy that is running: retrying will not help, and
    nothing is broken.
    """


class NotRunning(VeroError):
    """The worker is starting, restarting after a crash, or stopped.

    Nothing you did was wrong: wait, and say so in the interface.
    """


class Vero:
    """Runs a Go worker and talks to it."""

    def __init__(self, library_path: str, worker_path: str,
                 arguments: list[str] | None = None) -> None:
        # CDLL, not PyDLL: ctypes releases the interpreter lock for the
        # duration of a CDLL call, which is what lets wait_for_event block
        # without stopping every other Python thread.
        self._lib = ctypes.CDLL(library_path)
        self._declare()
        self._stopped = False

        args = json.dumps(arguments).encode() if arguments else b""
        self._check(self._lib.VeroStart(worker_path.encode(), args))

    def _declare(self) -> None:
        lib = self._lib
        # c_void_p rather than c_char_p on purpose: ctypes converts a
        # c_char_p result to bytes and throws the pointer away, and then
        # there is nothing left to free.
        for name, argtypes in (
            ("VeroStart", [ctypes.c_char_p, ctypes.c_char_p]),
            ("VeroRequest", [ctypes.c_char_p]),
            ("VeroCall", [ctypes.c_char_p, ctypes.c_char_p]),
            ("VeroLatest", []),
            ("VeroWaitForEvent", []),
            ("VeroState", []),
        ):
            fn = getattr(lib, name)
            fn.argtypes = argtypes
            fn.restype = ctypes.c_void_p
        lib.VeroStop.argtypes = []
        lib.VeroStop.restype = None
        lib.VeroFree.argtypes = [ctypes.c_void_p]
        lib.VeroFree.restype = None

    def _check(self, pointer: int | None) -> Any:
        """Read one envelope, free it, and raise if it carried an error."""
        if not pointer:
            raise NotRunning("the library returned nothing")
        try:
            raw = ctypes.cast(pointer, ctypes.c_char_p).value or b"{}"
            envelope = json.loads(raw)
        finally:
            self._lib.VeroFree(pointer)

        message = envelope.get("e")
        if message is not None:
            code = envelope.get("code")
            if code == "already_running":
                raise AlreadyRunning(message)
            if code == "not_running":
                raise NotRunning(message)
            if code == "refused":
                raise Refused(message)
            raise VeroError(message)
        return envelope.get("p")

    def send(self, request: Any) -> Any:
        """Send a request and wait for the reply.

        Returns None when the worker chose not to answer, which is normal for
        a request that only causes an action.  There is no timeout: a worker
        may hold a request for as long as the work takes, so call this off
        whatever thread draws your interface.
        """
        return self._check(self._lib.VeroRequest(json.dumps(request).encode()))

    def call(self, name: str, request: Any) -> Any:
        """Send a request to one named handler, matching vero.Handle on the worker.

        The same as send(), except the worker routes on the name rather than on
        something inside the request, so neither side has to agree on a "type"
        field.
        """
        return self._check(
            self._lib.VeroCall(name.encode(), json.dumps(request).encode())
        )

    def latest(self) -> Any:
        """The most recent event, without waiting for the next one.

        Use it to draw a window that has just opened; events() keeps it up to
        date afterwards.
        """
        return self._check(self._lib.VeroLatest())

    def state(self) -> str:
        """"starting", "running", "restarting" or "stopped"."""
        return self._check(self._lib.VeroState()) or "unknown"

    def events(self) -> Iterator[Any]:
        """Yield every state change the worker reports, as it happens.

        This blocks between events, so run it on its own thread and hand each
        one to your interface's main thread - GLib.idle_add under GTK.  There
        is no polling and no interval to choose: the worker sends one when
        something changes and nothing while it is quiet.
        """
        while not self._stopped:
            try:
                event = self._check(self._lib.VeroWaitForEvent())
            except NotRunning:
                return
            if event is not None:
                yield event

    def stop(self) -> None:
        """Stop the worker.

        Not required - the worker's standard input closes when this process
        exits and it stops with it, crash included - but it ends the work a
        moment sooner.
        """
        self._stopped = True
        self._lib.VeroStop()

    def __enter__(self) -> "Vero":
        return self

    def __exit__(self, *exc: object) -> None:
        self.stop()


def run_in_thread(vero: Vero, on_event) -> threading.Thread:
    """Convenience: read events on a daemon thread, calling on_event for each.

    on_event runs on that thread, not your interface's, so hop across before
    touching any widget.
    """
    def loop() -> None:
        for event in vero.events():
            on_event(event)

    thread = threading.Thread(target=loop, daemon=True)
    thread.start()
    return thread
