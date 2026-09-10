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

Both halves, from nothing. With Xcode and Go installed it takes a few minutes.

### 1. The worker

```bash
mkdir worker && cd worker
go mod init worker
go get github.com/calmdocs/vero
```

`main.go`:

```go
package main

import (
	"context"
	"sync"
	"time"

	"github.com/calmdocs/vero"
)

// What the interface draws.  One event type, widened when it needs more -
// see "Two things worth knowing" below.
type Job struct {
	ID       int    `json:"id"`
	Name     string `json:"name"`
	Progress int    `json:"progress"`
}

type Status struct {
	Jobs []Job `json:"jobs"`
}

// What the interface asks for.  The name it is registered under is what
// routes it, and Swift names the same string.
type RestartJob struct {
	ID int `json:"id"`
}

var (
	mu   sync.Mutex
	jobs = []Job{{ID: 1, Name: "Photos"}, {ID: 2, Name: "Documents"}}
)

func snapshot() Status {
	mu.Lock()
	defer mu.Unlock()
	return Status{Jobs: append([]Job(nil), jobs...)}
}

func main() {
	ctx := context.Background()
	w := vero.NewWorker(vero.WorkerOptions{})

	// The actual work.  Yours goes here.
	go func() {
		for range time.Tick(200 * time.Millisecond) {
			mu.Lock()
			for i := range jobs {
				if jobs[i].Progress < 100 {
					jobs[i].Progress++
				}
			}
			mu.Unlock()
		}
	}()

	// Push the state when it changes.  Not on a timer: an interface sent the
	// same thing ten times a second is polling with extra steps.
	go w.EmitOnChange(ctx, 100*time.Millisecond, func() any { return snapshot() })

	r := vero.NewRouter()
	vero.Handle(r, "restartJob", func(_ context.Context, req RestartJob) (Status, error) {
		mu.Lock()
		for i := range jobs {
			if jobs[i].ID == req.ID {
				jobs[i].Progress = 0
			}
		}
		mu.Unlock()
		return snapshot(), nil
	})

	// Blocks until the interface goes away, then returns so this process can
	// leave with it.
	w.Serve(r)
}
```

Build it as one universal binary:

```bash
GOOS=darwin GOARCH=amd64 go build -o worker-amd64 && \
GOOS=darwin GOARCH=arm64 go build -o worker-arm64 && \
lipo -create worker-amd64 worker-arm64 -output worker
```

That is the only binary you build. The C archive vero links ships with the
Swift package.

### 2. The app

Create a new macOS SwiftUI project, then File -> Add Package Dependencies... ->
`https://github.com/calmdocs/vero`, and drag `worker` into the project.

Replace `ContentView.swift` with this:

```swift
import SwiftUI
import Vero

// The same two types, and the same request name, as the worker.
struct Job: Decodable, Identifiable {
    let id: Int
    let name: String
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
    // Copies the worker out of the app bundle, launches it, restarts it if it
    // dies, stops it when the app exits, and republishes this view whenever
    // the worker pushes a new Status.
    @StateObject private var vero = VeroModel<Status>(
        bundledWorker: "worker", directoryName: "Example/bin")

    var body: some View {
        VStack(spacing: 0) {
            if let problem = vero.problem {
                Text(problem).foregroundStyle(.orange).padding(8)
            }
            List(vero.state?.jobs ?? []) { job in
                HStack {
                    Button { vero.call(RestartJob(id: job.id)) } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(vero.isBusy)

                    Text(job.name)
                    ProgressView(value: Double(job.progress) / 100)
                }
            }
        }
        .frame(minWidth: 320, minHeight: 200)
    }
}
```

### 3. Run it

Two jobs appear, their progress climbs, and the button sends a request that
sets one back to zero.

That is the whole interface to vero: `VeroModel` holds the worker and the last
state it pushed, `vero.state` is that state, and `vero.call` asks for
something. There is no supervisor to write, no polling, no in-flight counting
and no copying the worker out of the bundle - and `vero.worker` is there for
anything this does not cover.

## Two things worth knowing

**Emit one type.** The event envelope carries no name, so `events(T.self)`
decodes every payload as `T` and quietly skips what does not fit - telling
types apart by structural accident rather than by name. `latest` is a single
slot holding the most recent event whatever its type, so with two types a
window opening draws blank whenever the other one arrived last. Widen the type
you have rather than adding a second, which is what `EmitOnChange` and its
single snapshot already push you towards.

**A debug build always takes the worker from the bundle.** Rebuild a worker
without bumping its version and the copy on disk would otherwise stay - it is
the same version, so replacing it would be wrong - and the change under test
would never run, with nothing to say why. So in a debug build there is nothing
to remember: build the worker, run, and it is the one you just built.

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
