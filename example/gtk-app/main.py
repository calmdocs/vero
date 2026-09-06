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
CSS = b"""
window { background: #1c1c1e; }
.title { font-size: 19px; font-weight: bold; color: #f2f2f2; }
.count, .state { color: #949499; font-size: 12px; }
.card { background: #262628; border-radius: 10px; padding: 14px; }
.job { font-size: 15px; font-weight: bold; color: #f2f2f2; }
.sub { font-size: 12px; color: #949499; }
.icon { color: #949499; }
button.icon-button {
    background: none;
    background-image: none;
    border: none;
    box-shadow: none;
    padding: 4px;
    min-width: 0;
    min-height: 0;
}
button.icon-button:hover {
    background-color: alpha(#ffffff, 0.07);
    border-radius: 8px;
}
.badge {
    font-size: 11px;
    font-weight: bold;
    padding: 4px 10px;
    border-radius: 11px;
    background: alpha(#949499, 0.16);
    color: #949499;
}
.badge.done   { background: alpha(#5c9e75, 0.16); color: #5c9e75; }
.badge.upload { background: alpha(#5c82b0, 0.16); color: #5c82b0; }
.dot  { color: #5c9e75; font-size: 11px; }
.sep  { background: #333335; min-height: 1px; }
/* GTK4 nests these, and the theme paints the fill with a background-image
   gradient - so the shorthand alone leaves it looking empty. Both have to be
   set, and the image cleared. */
progressbar > trough {
    min-height: 6px;
    background-color: #38383a;
    background-image: none;
    border: none;
    border-radius: 3px;
}
progressbar > trough > progress {
    min-height: 6px;
    background-color: #5c82b0;
    background-image: none;
    border: none;
    border-radius: 3px;
}
button.flat { background: none; border: none; color: #949499; font-size: 12px; }
"""

ICONS = {
    "Photos": "image-x-generic-symbolic",
    "Documents": "x-office-document-symbolic",
    "Team share": "system-users-symbolic",
}

BADGE_CLASS = {"done": "done", "uploading": "upload"}


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

        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_display(
            self.get_display(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.set_child(outer)

        # Header
        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        header.set_margin_top(14); header.set_margin_bottom(14)
        header.set_margin_start(20); header.set_margin_end(20)
        title = Gtk.Label(label="vero", halign=Gtk.Align.START, hexpand=True)
        title.add_css_class("title")
        self.count = Gtk.Label(label="", halign=Gtk.Align.END)
        self.count.add_css_class("count")
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
        self.dot.add_css_class("dot")
        self.state = Gtk.Label(label="starting", hexpand=True, halign=Gtk.Align.START)
        self.state.add_css_class("state")
        quit_button = Gtk.Button(label="Quit")
        quit_button.add_css_class("flat")
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
        sep.add_css_class("sep")
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
            for c in ("done", "upload"):
                badge.remove_css_class(c)
            if (c := BADGE_CLASS.get(job["phase"])):
                badge.add_css_class(c)
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
        card.add_css_class("card")

        # A button, not a picture. The platform draws it, and it behaves the
        # way a button on this platform behaves - hover, focus ring, keyboard.
        icon = Gtk.Image.new_from_icon_name(ICONS.get(job["name"], "folder-symbolic"))
        icon.set_pixel_size(28)
        icon.add_css_class("icon")
        icon_button = Gtk.Button(child=icon, valign=Gtk.Align.CENTER)
        icon_button.add_css_class("icon-button")
        icon_button.set_tooltip_text("Restart")
        icon_button.connect("clicked", lambda *_: self.restart(job["id"]))
        card.append(icon_button)

        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6, hexpand=True)
        top = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        name = Gtk.Label(halign=Gtk.Align.START)
        name.add_css_class("job")
        badge = Gtk.Label(halign=Gtk.Align.START)
        badge.add_css_class("badge")
        top.append(name); top.append(badge)
        bar = Gtk.ProgressBar(hexpand=True)
        sub = Gtk.Label(label="Up to date", halign=Gtk.Align.START)
        sub.add_css_class("sub")
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
