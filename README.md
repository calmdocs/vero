# vero

**Write one Go app on a Mac, and build native applications for macOS, Windows
and Linux — all from that Mac.**

- Write the logic once, in Go.
- Draw each interface with the platform's own toolkit: SwiftUI, WPF, GTK.
- The two halves talk over pipes.
- Build and run all three from one Mac.

<table>
<tr>
<td align="center" width="33%"><img src="docs/screenshots/macos.gif" width="100%"><br><sub><b>macOS</b> — SwiftUI, in the menu bar</sub></td>
<td align="center" width="33%"><img src="docs/screenshots/windows.gif" width="100%"><br><sub><b>Windows</b> — WPF</sub></td>
<td align="center" width="33%"><img src="docs/screenshots/linux.gif" width="100%"><br><sub><b>Linux</b> — GTK4</sub></td>
</tr>
</table>

All three are recordings of the examples in this repository, running the same Go
worker. Each uses that platform's stock controls, with no styling applied.
[docs/styling.md](docs/styling.md) shows the same three with a design on top.

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

## Example

A macOS app with a Go worker behind it, in four steps. With Xcode and Go already
installed it takes about two minutes.

### 1. Create the project and add vero

Create a new macOS SwiftUI Xcode project, then add the package:

- File -> Add Package Dependencies... -> `https://github.com/calmdocs/vero`

### 2. Build the worker

```bash
git clone https://github.com/calmdocs/vero
cd vero/example/worker

GOOS=darwin GOARCH=amd64 go build -o worker-amd64 && \
GOOS=darwin GOARCH=arm64 go build -o worker-arm64 && \
lipo -create worker-amd64 worker-arm64 -output worker
```

Drag `worker` into your Xcode project.

That is the only binary you build. The C archive vero links is the same for
every application, so the Swift package ships it.

### 3. Write the interface

Replace `ContentView.swift` with this:

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

### 4. Run it

Three jobs appear, their progress moves, and the button sends a request back to
the worker.

### The Go side

The worker is [example/worker/main.go](example/worker/main.go). This is all of
its interface to Swift:

```go
r := vero.NewRouter()

vero.Handle(r, "restartJob", func(_ context.Context, req RestartJob) (Status, error) {
    return restart(req.ID)
})

// Push an event when the state changes, not on a timer.
go w.EmitOnChange(ctx, 100*time.Millisecond, func() any { return snapshot() })

w.Serve(r)
```

## The three examples

The same worker behind three interfaces. Each one is small and has a README.

- **macOS** (SwiftUI) — [example/menubar-app](example/menubar-app), the example
  above as a menu bar app
- **Windows** (WPF, C#) — [example/wpf-app](example/wpf-app)
- **Linux** (GTK4, Python) — [example/gtk-app](example/gtk-app)

Build and run all three from the Mac, with two commands:

```bash
./scripts/setup.sh                                   # install toolchains, then build
./scripts/run.sh --iso ~/Downloads/win11.iso         # open all three
```

The `--iso` is a Windows 11 Arm64 ISO, and is only needed the first time:
`run.sh` installs Windows into a VM once, and reuses it after that.

| Script | What it does |
|---|---|
| `scripts/setup.sh` | installs any missing toolchain, then builds everything |
| `scripts/build-all.sh` | builds every artefact, for all three platforms, into `dist/` |
| `scripts/run.sh` | opens the example on all three platforms at once |
| `scripts/run-linux.sh` | runs the GTK example in a window on your Mac |
| `scripts/run-windows.sh` | runs a Windows VM with your build on a disc |
| `scripts/release.sh` | packages one archive per platform, plus checksums |

[Building and running from a Mac](docs/building.md) is what these scripts do,
written out step by step.

## More

- [How it fits together](docs/design.md) - what runs where, and why pipes
- [The protocol](docs/protocol.md) - the wire format, errors, the single-worker lock
- [Building and running from a Mac](docs/building.md) - every build command, by hand
- [The styling](docs/styling.md) - the same examples with a design on them

## Tests

```bash
go test -race ./...
cd bindings/python && python3 -m unittest
swift build
```

The Go tests run the test binary as their own worker, so it is a real separate
process. The Python tests build the shared library and the example worker
first.

## Licence

MIT
