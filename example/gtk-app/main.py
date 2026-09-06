#!/usr/bin/env python3
"""A GTK4 interface for the worker in ../worker.

    ./build.sh
    ./main.py

Shows each job's progress, with a Restart button on the ones that have
finished - the GTK counterpart of the SwiftUI menu bar example.

Run under Xvfb in a Debian container on a Mac - see "Running them without the
hardware" in the top-level README, which is also how the recording in it was
made.
"""

import os
import sys

import gi

gi.require_version("Gtk", "4.0")
from gi.repository import GLib, Gtk  # noqa: E402

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../../bindings/python"))
from vero import NotRunning, Refused, Vero, run_in_thread  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))


# Muted on purpose, and the same palette as the macOS example.
#
# Colour carries meaning rather than decorating: ordinary progress is neutral,
# because "looking for changes" is not a warning and should not look like one,
# and only finishing earns a colour. That is what leaves amber worth noticing
# when something is actually wrong.
ICONS = {
    "Photos": "image-x-generic-symbolic",
    "Documents": "x-office-document-symbolic",
    "Team share": "system-users-symbolic",
}


class Window(Gtk.ApplicationWindow):
    """The same shape as the macOS example, in GTK.

    Only the drawing differs: the worker, the protocol and the state it
    publishes are identical, because they are the same Go program.
    """

    def __init__(self, app: Gtk.Application, vero: Vero) -> None:
        super().__init__(application=app, title="vero")
        self.vero = vero
        self.rows: dict[int, dict] = {}
        self.set_default_size(380, 0)

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.set_child(outer)

        # Header
        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        header.set_margin_top(14); header.set_margin_bottom(14)
        header.set_margin_start(20); header.set_margin_end(20)
        title = Gtk.Label(label="vero", halign=Gtk.Align.START, hexpand=True)
        self.count = Gtk.Label(label="", halign=Gtk.Align.END)
        header.append(title); header.append(self.count)
        outer.append(header)
        outer.append(self._separator())

        # Jobs
        self.jobs = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.jobs.set_margin_top(16); self.jobs.set_margin_bottom(16)
        self.jobs.set_margin_start(16); self.jobs.set_margin_end(16)
        outer.append(self.jobs)

        # Footer
        outer.append(self._separator())
        footer = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        footer.set_margin_top(10); footer.set_margin_bottom(10)
        footer.set_margin_start(20); footer.set_margin_end(20)
        self.dot = Gtk.Label(label="\u25cf")
        self.state = Gtk.Label(label="starting", hexpand=True, halign=Gtk.Align.START)
        quit_button = Gtk.Button(label="Quit")
        quit_button.connect("clicked", lambda *_: app.quit())
        footer.append(self.dot); footer.append(self.state); footer.append(quit_button)
        outer.append(footer)

        try:
            if (status := self.vero.latest()):
                self.apply(status)
        except NotRunning:
            pass

        run_in_thread(self.vero, lambda s: GLib.idle_add(self.apply, s))
        GLib.timeout_add(500, self.refresh_state)

    def _separator(self) -> Gtk.Widget:
        sep = Gtk.Box()
        return sep

    def refresh_state(self) -> bool:
        self.state.set_text(self.vero.state())
        return True

    def apply(self, status: dict) -> bool:
        jobs = status["jobs"]
        self.count.set_text(f"{len(jobs)} job{'' if len(jobs) == 1 else 's'}")
        for job in jobs:
            if job["id"] not in self.rows:
                self.add_row(job)
            row = self.rows[job["id"]]
            row["name"].set_text(job["name"])
            badge = row["badge"]
            badge.set_text(job["phase"])
            row["bar"].set_fraction(job["progress"] / 100)
            done = job["phase"] == "done"
            row["bar"].set_visible(not done)
            row["sub"].set_visible(done)
        return False

    def restart(self, job_id: int) -> None:
        """Ask the worker to run this job again.

        call() names the handler on the worker - "restartJob" is registered
        there with vero.Handle - and the reply is the new status, so the window
        redraws without waiting for the next event.
        """
        try:
            self.apply(self.vero.call("restartJob", {"id": job_id}))
        except Refused as message:
            # The worker got it and said no. It is still there, so this is
            # worth showing; "not running" would not be.
            self.state.set_text(str(message))
        except NotRunning:
            pass

    def add_row(self, job: dict) -> None:
        card = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=14)

        # A button, not a picture. The platform draws it, and it behaves the
        # way a button on this platform behaves - hover, focus ring, keyboard.
        icon = Gtk.Image.new_from_icon_name(ICONS.get(job["name"], "folder-symbolic"))
        icon.set_pixel_size(28)
        icon_button = Gtk.Button(child=icon, valign=Gtk.Align.CENTER)
        icon_button.set_tooltip_text("Restart")
        icon_button.connect("clicked", lambda *_: self.restart(job["id"]))
        card.append(icon_button)

        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6, hexpand=True)
        top = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        name = Gtk.Label(halign=Gtk.Align.START)
        badge = Gtk.Label(halign=Gtk.Align.START)
        top.append(name); top.append(badge)
        bar = Gtk.ProgressBar(hexpand=True)
        sub = Gtk.Label(label="Up to date", halign=Gtk.Align.START)
        sub.set_visible(False)
        body.append(top); body.append(bar); body.append(sub)
        card.append(body)

        self.jobs.append(card)
        self.rows[job["id"]] = {"name": name, "badge": badge, "bar": bar, "sub": sub}


class Application(Gtk.Application):
    def __init__(self) -> None:
        super().__init__(application_id="com.calmdocs.vero.example")
        self.vero: Vero | None = None

    def do_activate(self) -> None:
        if self.vero is None:
            self.vero = Vero(os.path.join(HERE, "libvero.so"),
                             os.path.join(HERE, "worker"))
        Window(self, self.vero).present()

    def do_shutdown(self) -> None:
        # Not required - the worker's stdin closes when we exit and it goes
        # with us - but it stops the work a moment sooner.
        if self.vero:
            self.vero.stop()
        Gtk.Application.do_shutdown(self)


if __name__ == "__main__":
    sys.exit(Application().run(sys.argv))
