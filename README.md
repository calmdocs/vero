# vero

**A Go backend with native macOS, Windows and Linux frontends.**

<table>
<tr>
<td align="center" width="33%"><img src="docs/screenshots/macos.gif" width="100%"><br><sub><b>macOS</b> — SwiftUI, in the menu bar</sub></td>
<td align="center" width="33%"><img src="docs/screenshots/windows.gif" width="100%"><br><sub><b>Windows</b> — WPF</sub></td>
<td align="center" width="33%"><img src="docs/screenshots/linux.gif" width="100%"><br><sub><b>Linux</b> — GTK4</sub></td>
</tr>
</table>

## Run the examples

```bash
git clone https://github.com/calmdocs/vero && cd vero
./scripts/setup.sh                              # installs toolchains, builds everything
./scripts/run.sh --iso ~/Downloads/win11.iso    # opens all three
```

`--iso` is a Windows 11 Arm64 ISO, needed only the first time.

## Add vero to your own macOS app

With Xcode and Go installed, this is a working app in four steps.

**1.** Create a new macOS SwiftUI project, then File -> Add Package
Dependencies... -> `https://github.com/calmdocs/vero`

**2.** Build the worker, and drag it into the project. This is the only binary
you build — the C archive vero links ships with the Swift package.

```bash
git clone https://github.com/calmdocs/vero && cd vero/example/worker
GOOS=darwin GOARCH=amd64 go build -o worker-amd64 && \
GOOS=darwin GOARCH=arm64 go build -o worker-arm64 && \
lipo -create worker-amd64 worker-arm64 -output worker
```

**3.** Replace `ContentView.swift` with this:

```swift
import SwiftUI
import Vero

// What the worker sends us. The keys match the json tags on the go structs.
struct Job: Decodable, Identifiable {
    let id: Int
    let name: String
    let phase: String
    let progress: Int
}

struct Status: Decodable {
    let jobs: [Job]
}

// What we send back. `name` is the handler it is routed to - it matches
// vero.Handle in the worker - and Reply is what comes back.
struct RestartJob: NamedRequest {
    static let name = "restartJob"
    typealias Reply = Status
    let id: Int
}

struct ContentView: View {
    @StateObject private var model = Model()

    var body: some View {
        VStack(spacing: 0) {
            if let problem = model.problem {
                Text(problem).foregroundStyle(.orange).padding(8)
            }
            List(model.jobs) { job in
                HStack {
                    Button { model.restart(job) } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(model.worker?.isBusy ?? true)

                    Text(job.name)
                    Text(job.phase).foregroundStyle(.secondary)
                    ProgressView(value: Double(job.progress) / 100)
                }
            }
        }
        .frame(minWidth: 380, minHeight: 220)
        .onAppear { model.start() }
    }
}

@MainActor
final class Model: ObservableObject {
    @Published var jobs: [Job] = []
    @Published var problem: String?

    // Published so the view can read worker.isBusy and worker.state directly.
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
            problem = "Could not start the worker: \(error.localizedDescription)"
        }
    }

    func restart(_ job: Job) {
        // No await: this overload is for buttons.
        worker?.call(RestartJob(id: job.id))
    }
}
```

**4.** Run it. Three jobs appear, their progress moves, and the button sends a
request to the worker.

### The go side

That worker is [example/worker/main.go](example/worker/main.go), and this is
all of its interface to Swift:

```go
r := vero.NewRouter()

vero.Handle(r, "restartJob", func(_ context.Context, req RestartJob) (Status, error) {
    return restart(req.ID)
})

// Push an event when the state changes, not on a timer.
go w.EmitOnChange(ctx, 100*time.Millisecond, func() any { return snapshot() })

w.Serve(r)
```

## Next

| | |
|---|---|
| [example/menubar-app](example/menubar-app) | the macOS example in full (SwiftUI) |
| [example/wpf-app](example/wpf-app) · [example/gtk-app](example/gtk-app) | the same worker on Windows and Linux |
| [docs/building.md](docs/building.md) | every build command, and what each script does |
| [docs/design.md](docs/design.md) | what runs where, and why pipes |
| [docs/protocol.md](docs/protocol.md) | wire format, errors, the single-worker lock |
| [docs/styling.md](docs/styling.md) | the same examples with a design on them |

## Tests

```bash
go test -race ./...
cd bindings/python && python3 -m unittest
swift build
```

## Licence

MIT
