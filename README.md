# vero

**Desktop applications whose logic is written once, in Go, and whose interface
is the platform's own toolkit.**

Every other way of building a desktop app in Go asks you to give something up.
Fyne and Gio draw their own widgets, so the result looks identical everywhere
and native nowhere. Wails and Lorca wrap a webview, which is Electron's
tradeoff in a smaller binary. Walk is Windows only.

vero takes the fourth path. The interface is genuinely SwiftUI, or WPF, or
GTK — real controls, real menus, real notifications — and Go supplies
everything behind it.

<table>
<tr>
<td align="center" width="33%"><img src="docs/screenshots/macos.gif" width="100%"><br><sub><b>macOS</b> — SwiftUI, in the menu bar</sub></td>
<td align="center" width="33%"><img src="docs/screenshots/windows.gif" width="100%"><br><sub><b>Windows</b> — WPF</sub></td>
<td align="center" width="33%"><img src="docs/screenshots/linux.gif" width="100%"><br><sub><b>Linux</b> — GTK4</sub></td>
</tr>
</table>

All three are the same Go worker. Only the drawing differs — and all three are
recordings of the examples in this repository actually running: one on a Mac,
one on Windows 11 in a VM, and one under Xvfb in a container.

Everything you can see is a real control drawn by the platform. The icon on the
left of each row is a button, not a picture of one: it hovers, takes focus and
answers the keyboard the way a button on that platform does, because it *is*
one. Nothing is polling either — the progress moving is the worker pushing an
event each time its state changes.

### How much of that is vero?

None of it. Those are stock controls with no styling at all - what the platform
gives you for free, which is why they look like three different applications
rather than one design painted three times.

[docs/styling.md](docs/styling.md) has the same three with a design on top, and
the code that does it. It is worth a look if you want the polished version, and
worth ignoring entirely if you do not.

```
   SwiftUI           WPF             GTK
  ┌─────────┐    ┌─────────┐    ┌─────────┐
  │  macOS  │    │ Windows │    │  Linux  │   the platform's own controls
  └────┬────┘    └────┬────┘    └────┬────┘
       └──────────────┼──────────────┘
                 ┌────┴────┐
                 │ your Go │                 one implementation
                 └─────────┘
```

If you already have Xcode and Go installed, the example below takes about two
minutes and gives you a running app.

## Example

### Setup

Create a new macOS SwiftUI Xcode project, then:

- File -> Add Package Dependencies... -> `https://github.com/calmdocs/vero`

### Build the worker

```bash
git clone https://github.com/calmdocs/vero
cd vero/example/worker

GOOS=darwin GOARCH=amd64 go build -o worker-amd64 && \
GOOS=darwin GOARCH=arm64 go build -o worker-arm64 && \
lipo -create worker-amd64 worker-arm64 -output worker
```

Drag `worker` into your Xcode project. That is the only binary you build: the C
archive behind vero is the same for every application, so the package brings its
own and links it for you.

### In the new Xcode project, replace ContentView.swift with the following code:

```swift
import SwiftUI
import Vero

// What the worker sends us, and what we send back. The name on RestartJob is
// the handler it is routed to - it matches vero.Handle in the go worker.
struct Job: Decodable, Identifiable {
    let id: Int
    let name: String
    let phase: String
    let progress: Int
}

struct Status: Decodable {
    let jobs: [Job]
}

struct RestartJob: NamedRequest {
    static let name = "restartJob"
    typealias Reply = Status
    let id: Int
}

struct ContentView: View {
    @StateObject private var model = Model()

    var body: some View {
        List(model.jobs) { job in
            HStack {
                Text(job.name)
                Text(job.phase).foregroundStyle(.secondary)
                ProgressView(value: Double(job.progress) / 100)
                Button {
                    model.restart(job)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(model.worker?.isBusy ?? true)
            }
        }
        .onAppear { model.start() }
    }
}

@MainActor
final class Model: ObservableObject {
    @Published var jobs: [Job] = []
    @Published private(set) var worker: VeroClient?

    func start() {
        guard worker == nil else { return }
        do {
            // Copies the worker out of the app bundle, launches it, restarts
            // it if it dies, and stops it when this app exits.
            let worker = try VeroClient(
                bundledWorker: "worker", directoryName: "Example/bin")

            // Pushed the instant the go side changes, already on the main
            // actor, so it can go straight into published state.
            worker.onEvent(Status.self) { [weak self] status in
                self?.jobs = status.jobs
            }
            if let status = worker.latest(Status.self) { jobs = status.jobs }

            self.worker = worker
        } catch {
            print("could not start the worker:", error.localizedDescription)
        }
    }

    func restart(_ job: Job) {
        worker?.call(RestartJob(id: job.id))
    }
}
```

Run it. Three jobs appear and their progress moves, pushed from Go as it
changes - nothing polls. The button sends a request back.

That is close to what the recordings above show, because the examples use stock
controls too. The macOS one, [example/menubar-app](example/menubar-app), is this
in a menu bar rather than a window, with an empty state and an error line.

### The go side

The worker is [example/worker/main.go](example/worker/main.go), and this is all
of the interface to Swift:

```go
r := vero.NewRouter()

vero.Handle(r, "restartJob", func(_ context.Context, req RestartJob) (Status, error) {
    return restart(req.ID)
})

// Push an event when the state changes, not on a timer.
go w.EmitOnChange(ctx, 100*time.Millisecond, func() any { return snapshot() })

w.Serve(r)
```

Returning an error from a handler is not a crash: it arrives in Swift as
`VeroError.refused`, with the worker still running.

## Windows and Linux

The same worker, behind WPF and GTK4. Each example is small and has a README.

- [example/wpf-app](example/wpf-app) - C#
- [example/gtk-app](example/gtk-app) - Python
- [example/menubar-app](example/menubar-app) - the macOS example above, as a menu bar app

You can build and run all three from the Mac:

```bash
./scripts/setup.sh                                   # toolchains, then build
./scripts/run.sh --iso ~/Downloads/win11.iso         # opens all three
```

| script | |
|---|---|
| `scripts/setup.sh` | installs whatever toolchain is missing, then builds everything |
| `scripts/run.sh` | opens the example on all three at once |
| `scripts/build-all.sh` | every artefact, for all three, into `dist/` |
| `scripts/release.sh` | one archive per platform, plus checksums |
| `scripts/run-linux.sh` | the GTK example in a window on your Mac |
| `scripts/run-windows.sh` | a Windows VM with your build on a disc |

## More

- [How it fits together](docs/design.md) - what runs where, and why pipes
- [The protocol](docs/protocol.md) - the wire format, errors, the single-worker lock
- [Building and running from a Mac](docs/building.md) - the long way round, by hand
- [The styling](docs/styling.md) - the same examples with a design on them

## Tests

```bash
go test -race ./...
cd bindings/python && python3 -m unittest
swift build
```

The Go tests run the test binary as their own worker, so the worker really is
a separate process: crashes, restarts, concurrent requests and the lifecycle
are all exercised against a real one. The Python tests build the shared
library and the example worker and drive the whole stack through ctypes.

## Licence

MIT
