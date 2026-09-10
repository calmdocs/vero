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

## Add vero to your own app

**1.** In Xcode: File -> Add Package Dependencies... ->
`https://github.com/calmdocs/vero`

**2.** Build the worker and drag it into your project. This is the only binary
you build — the C archive vero links ships with the Swift package.

```bash
cd vero/example/worker
GOOS=darwin GOARCH=amd64 go build -o worker-amd64 && \
GOOS=darwin GOARCH=arm64 go build -o worker-arm64 && \
lipo -create worker-amd64 worker-arm64 -output worker
```

**3.** Swift — launch it, receive events, send requests back:

```swift
import Vero

struct Job: Decodable, Identifiable { let id: Int; let name: String; let progress: Int }
struct Status: Decodable { let jobs: [Job] }

struct RestartJob: NamedRequest {      // name matches vero.Handle in the worker
    static let name = "restartJob"
    typealias Reply = Status
    let id: Int
}

// Copies the worker out of the bundle, launches it, restarts it if it dies,
// and stops it when the app exits.
let worker = try VeroClient(bundledWorker: "worker", directoryName: "Example/bin")

// Pushed the instant the go side changes, already on the main actor.
worker.onEvent(Status.self) { status in self.jobs = status.jobs }

worker.call(RestartJob(id: job.id))
```

**4.** Go — the whole interface to Swift:

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
