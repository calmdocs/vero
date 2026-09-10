# vero

**A Go backend with native macOS, Windows and Linux frontends.**

<table>
<tr>
<td align="center" width="33%"><img src="docs/screenshots/macos.gif" width="100%"><br><sub><b>macOS</b> — SwiftUI, in the menu bar</sub></td>
<td align="center" width="33%"><img src="docs/screenshots/windows.gif" width="100%"><br><sub><b>Windows</b> — WPF</sub></td>
<td align="center" width="33%"><img src="docs/screenshots/linux.gif" width="100%"><br><sub><b>Linux</b> — GTK4</sub></td>
</tr>
</table>

## Add vero to your own macOS app

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
	"fmt"
	"sync"
	"time"

	"github.com/calmdocs/vero"
)

// What the interface draws.
type Job struct {
	ID       int    `json:"id"`
	Name     string `json:"name"`
	Progress int    `json:"progress"`
}

type Status struct {
	Jobs []Job `json:"jobs"`
}

// What the interface asks for.  The name each is registered under is what
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

	// Add a job.  The reply is the new state, so the interface cannot draw
	// the list from before its own change.
	vero.Handle(r, "addJob", func(_ context.Context, _ struct{}) (Status, error) {
		mu.Lock()
		n := len(jobs) + 1
		jobs = append(jobs, Job{ID: n, Name: fmt.Sprintf("Job %d", n)})
		mu.Unlock()
		return snapshot(), nil
	})

	// Send one back to the beginning.
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

// The same two types, and the same request names, as the worker.
struct Job: Decodable, Identifiable {
    let id: Int
    let name: String
    let progress: Int
}

struct Status: Decodable {
    let jobs: [Job]
}

struct AddJob: NamedRequest {
    static let name = "addJob"
    typealias Reply = Status
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
            HStack {
                Button("Add job") { vero.call(AddJob()) }
                    .disabled(vero.isBusy)
                Spacer()
                if let problem = vero.problem {
                    Text(problem).foregroundStyle(.orange)
                }
            }
            .padding(8)

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
        .frame(minWidth: 320, minHeight: 240)
    }
}
```

### 3. Run it

Two jobs appear and their progress climbs. **Add job** puts a third in the
list, and the arrow beside a job sends it back to the beginning.

## The same worker, on Windows and Linux

Same `main.go`. Each interface needs the worker built for that platform, plus
the C shared library built from [cshim](cshim) - which macOS does not, because
the Swift package ships the archive.

### Windows — WPF, C#

Built from your Mac. WPF needs Windows to run, not to build.

```bash
CGO_ENABLED=1 GOOS=windows GOARCH=arm64 CC=aarch64-w64-mingw32-clang \
    go build -buildmode=c-shared -o vero.dll github.com/calmdocs/vero/cshim
CGO_ENABLED=0 GOOS=windows GOARCH=arm64 go build -o worker.exe .

dotnet publish -c Release -r win-arm64 --self-contained \
    -p:EnableWindowsTargeting=true -o out
cp vero.dll worker.exe out/
```

On x64, swap `arm64` for `amd64`, `win-arm64` for `win-x64`, and use
`CC=x86_64-w64-mingw32-gcc` from `brew install mingw-w64`. Build `vero.dll` for
the architecture you will run on: an amd64 build under emulation on
Windows-on-ARM either hangs on the first call into Go or exits `0xC0000409`.

Keep both filenames. `vero.dll` is loaded by name, and the worker is looked for
beside the executable.

[example/wpf-app](example/wpf-app) · [bindings/csharp](bindings/csharp)

### Linux — GTK4, Python

Both pieces have to be built on Linux: `-buildmode=c-shared` on a Mac produces
a Mach-O dylib, not an ELF shared object.

```bash
CGO_ENABLED=1 go build -buildmode=c-shared -o libvero.so github.com/calmdocs/vero/cshim
go build -o worker .
```

Needs `python3-gi` and `gir1.2-gtk-4.0`. From a Mac, `./scripts/run-linux.sh`
builds both in a container and opens the app in Screen Sharing.

[example/gtk-app](example/gtk-app) · [bindings/python](bindings/python)

## Run all three

```bash
git clone https://github.com/calmdocs/vero && cd vero
./scripts/setup.sh                              # installs toolchains, builds everything
./scripts/run.sh --iso ~/Downloads/win11.iso    # opens all three
```

`--iso` is a Windows 11 Arm64 ISO, needed only the first time: `run.sh`
installs Windows into a VM once and reuses it after that.

## More

| | |
|---|---|
| [example/menubar-app](example/menubar-app) | the macOS example in full (SwiftUI) |
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
