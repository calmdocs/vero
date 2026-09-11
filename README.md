# vero

**A Go backend with native macOS, Windows and Linux frontends. All built on macOS.**

[macOS](#macos-add-vero-to-your-own-macos-app) ·
[Windows](#windows-add-the-same-worker-to-a-windows-app) ·
[Linux](#linux-add-the-same-worker-to-a-linux-app) ·
[All three at once](#set-up-and-run-all-three-apps-in-three-lines) ·
[More](#more) ·
[Tests](#tests)

<table>
<tr>
<td align="center" width="33%"><a href="#macos-add-vero-to-your-own-macos-app"><img src="docs/screenshots/macos.gif" width="100%"></a><br><sub><b>macOS</b> — SwiftUI, in the menu bar</sub></td>
<td align="center" width="33%"><a href="#windows-add-the-same-worker-to-a-windows-app"><img src="docs/screenshots/windows.gif" width="100%"></a><br><sub><b>Windows</b> — WPF</sub></td>
<td align="center" width="33%"><a href="#linux-add-the-same-worker-to-a-linux-app"><img src="docs/screenshots/linux.gif" width="100%"></a><br><sub><b>Linux</b> — GTK4</sub></td>
</tr>
</table>

## macOS: Add vero to your own macOS app

### 1. The go worker

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

### 2. The macOS SwiftUI app

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

## Windows: Add the same worker to a Windows app

The `main.go` from step 1 is unchanged, and every step below runs on your
Mac. Only step 4 needs Windows.

Install these once:

| | |
|---|---|
| The .NET SDK | `brew install --cask dotnet-sdk` |
| A Windows ARM64 C compiler | unpack the `macos-universal` release of [llvm-mingw](https://github.com/mstorsjo/llvm-mingw/releases) into `~/toolchains/llvm-mingw` |

Match the Windows machine you will run on, not the Mac you are building on.
Every step below targets ARM. For an x64 machine, three things change:

- the compiler is `x86_64-w64-mingw32-gcc`, from `brew install mingw-w64`
- both commands in step 1 take `GOARCH=amd64`
- step 3 publishes `-r win-x64`

### 1. The go worker, and the library

In the `worker` directory from step 1:

```bash
CGO_ENABLED=1 GOOS=windows GOARCH=arm64 \
    CC=$HOME/toolchains/llvm-mingw/bin/aarch64-w64-mingw32-clang \
    go build -buildmode=c-shared -o vero.dll github.com/calmdocs/vero/cshim
CGO_ENABLED=0 GOOS=windows GOARCH=arm64 go build -o worker.exe .
```

### 2. The Windows WPF app

Make a directory beside `worker` and copy
[bindings/csharp/Vero.cs](bindings/csharp/Vero.cs) into it. Add these four
files:

`VeroExample.csproj`:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>WinExe</OutputType>
    <TargetFramework>net8.0-windows</TargetFramework>
    <UseWPF>true</UseWPF>
    <Nullable>enable</Nullable>
    <RootNamespace>VeroExample</RootNamespace>
  </PropertyGroup>
</Project>
```

`App.xaml`:

```xml
<Application x:Class="VeroExample.App"
             xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             StartupUri="MainWindow.xaml"/>
```

`MainWindow.xaml`:

```xml
<Window x:Class="VeroExample.MainWindow"
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="vero" Width="360" Height="260">
    <DockPanel Margin="8">
        <Button x:Name="AddJob" Content="Add job" Click="AddJob_Click"
                DockPanel.Dock="Top" HorizontalAlignment="Left" Padding="8,2"/>
        <ItemsControl x:Name="Jobs" Margin="0,8,0,0">
            <ItemsControl.ItemTemplate>
                <DataTemplate>
                    <DockPanel Margin="0,4">
                        <Button Content="&#x21bb;" Tag="{Binding Id}" Click="Restart_Click"/>
                        <TextBlock Text="{Binding Name}" Width="90" Margin="8,0"/>
                        <ProgressBar Value="{Binding Progress}" Maximum="100" Height="12"/>
                    </DockPanel>
                </DataTemplate>
            </ItemsControl.ItemTemplate>
        </ItemsControl>
    </DockPanel>
</Window>
```

`MainWindow.xaml.cs`:

```csharp
using System;
using System.Collections.ObjectModel;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Windows;
using System.Windows.Controls;
using Vero;

namespace VeroExample;

// The same types, and the same request names, as the worker.
public record Job(
    [property: JsonPropertyName("id")]       int Id,
    [property: JsonPropertyName("name")]     string Name,
    [property: JsonPropertyName("progress")] int Progress);

public record Status(
    [property: JsonPropertyName("jobs")] Job[] Jobs);

public partial class MainWindow : Window
{
    private readonly VeroClient _vero;
    private readonly ObservableCollection<Job> _jobs = new();

    public MainWindow()
    {
        InitializeComponent();
        Jobs.ItemsSource = _jobs;

        // Launches the worker beside the executable, restarts it if it dies,
        // and stops it when this process exits.
        _vero = new VeroClient(Path.Combine(
            AppDomain.CurrentDomain.BaseDirectory, "worker.exe"));

        _ = ReadEvents();
    }

    // Pushed the instant the worker's state moves, on its own thread.
    private async System.Threading.Tasks.Task ReadEvents()
    {
        await foreach (var element in _vero.Events())
        {
            var status = element.Deserialize<Status>();
            if (status is not null)
                Dispatcher.Invoke(() => Apply(status));
        }
    }

    private void Apply(Status status)
    {
        _jobs.Clear();
        foreach (var job in status.Jobs) _jobs.Add(job);
    }

    private async void AddJob_Click(object sender, RoutedEventArgs e) =>
        await _vero.CallAsync("addJob", new { });

    private async void Restart_Click(object sender, RoutedEventArgs e) =>
        await _vero.CallAsync("restartJob", new { id = (int)((Button)sender).Tag });
}
```

### 3. Build it

```bash
dotnet publish -c Release -r win-arm64 --self-contained \
    -p:EnableWindowsTargeting=true -o out
cp ../worker/vero.dll ../worker/worker.exe out/
```

Keep both names: `Vero.cs` imports `vero.dll` by name, and `MainWindow.xaml.cs`
looks for `worker.exe` beside the executable.

### 4. Run it

Copy `out/` to a Windows machine and run `VeroExample.exe`. Two jobs appear
and their progress climbs. **Add job** puts a third in the list, and the arrow
beside a job sends it back to the beginning.

No Windows machine? `./scripts/run-windows.sh` boots one in a VM on your Mac
with this build on a disc. [example/wpf-app](example/wpf-app) is the Windows
example in full: the same app with job phases and a status footer.

## Linux: Add the same worker to a Linux app

The `main.go` from step 1 is unchanged, and every step below runs on your Mac
as well. The library is built in a container, because `-buildmode=c-shared` on
a Mac emits a Mach-O dylib rather than an ELF shared object.

Install Docker once:

```bash
brew install colima docker && colima start
```

### 1. The go worker, and the library

Run these in the `worker` directory from step 1, which has to sit somewhere
under your home directory: colima shares only `$HOME` with the container, so a
build mounted from anywhere else finishes without error and leaves no files.

```bash
docker run --rm -v "$PWD":/src -w /src \
    -e GOCACHE=/tmp/gocache -e GOPATH=/tmp/go -e GOTOOLCHAIN=auto \
    golang:1.24-bookworm \
    sh -c 'CGO_ENABLED=1 go build -buildmode=c-shared -o libvero.so github.com/calmdocs/vero/cshim'

CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -o worker-linux .
```

### 2. The Linux GTK4 app

Make a directory beside `worker` and copy
[bindings/python/vero.py](bindings/python/vero.py) into it, along with the two
files from step 1:

```bash
cp ../worker/libvero.so .
cp ../worker/worker-linux worker
```

Those are the names `main.py` uses: it loads `libvero.so` and runs `worker`
from its own directory, which is why the second copy drops the `-linux`. Add
`main.py` next:

```python
#!/usr/bin/env python3
import os
import gi

gi.require_version("Gtk", "4.0")
from gi.repository import GLib, Gtk

from vero import Vero, run_in_thread

HERE = os.path.dirname(os.path.abspath(__file__))


class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="vero", default_width=360)
        self.bars = {}

        # Launches the worker beside this file, restarts it if it dies, and
        # stops it when this process exits.
        self.vero = Vero(os.path.join(HERE, "libvero.so"),
                         os.path.join(HERE, "worker"))

        add = Gtk.Button(label="Add job")
        add.connect("clicked", lambda _: self.vero.call("addJob", {}))

        self.rows = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8,
                      margin_top=8, margin_bottom=8, margin_start=8, margin_end=8)
        box.append(add)
        box.append(self.rows)
        self.set_child(box)

        # latest draws a window that has just opened; events keep it current.
        if status := self.vero.latest():
            self.apply(status)
        run_in_thread(self.vero, lambda s: GLib.idle_add(self.apply, s))

    def apply(self, status):
        for job in status["jobs"]:
            if job["id"] not in self.bars:
                self.bars[job["id"]] = self.add_row(job)
            self.bars[job["id"]].set_fraction(job["progress"] / 100)
        return False  # GLib.idle_add: run once

    def add_row(self, job):
        bar = Gtk.ProgressBar(hexpand=True, valign=Gtk.Align.CENTER)
        restart = Gtk.Button(icon_name="view-refresh-symbolic")
        restart.connect(
            "clicked", lambda _, i=job["id"]: self.vero.call("restartJob", {"id": i}))

        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        row.append(restart)
        row.append(Gtk.Label(label=job["name"], width_chars=10, xalign=0))
        row.append(bar)
        self.rows.append(row)
        return bar


app = Gtk.Application(application_id="com.example.vero")
app.connect("activate", lambda a: Window(a).present())
app.run(None)
```

### 3. Run it

On a Linux machine, install `python3-gi` and `gir1.2-gtk-4.0`, then:

```bash
chmod +x main.py && ./main.py
```

Or run it from your Mac, on a virtual display in a container, and watch it in
Screen Sharing:

```bash
docker build -t vero-gtk - <<'EOF'
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-gi gir1.2-gtk-4.0 libgtk-4-1 xvfb x11vnc xauth \
    && rm -rf /var/lib/apt/lists/*
EOF

docker run --rm -p 5901:5900 -v "$PWD":/app -w /app vero-gtk sh -c '
    Xvfb :99 -screen 0 480x440x24 &
    sleep 2
    export DISPLAY=:99
    python3 main.py &
    sleep 4
    x11vnc -display :99 -forever -nopw -listen 0.0.0.0'

open vnc://localhost:5901
```

Two jobs appear and their progress climbs. **Add job** puts a third in the
list, and the arrow beside a job sends it back to the beginning.

[example/gtk-app](example/gtk-app) is the Linux example in full: the same app
with job phases and a status footer. `./scripts/run-linux.sh` runs it this way
in one command.

## Set up and run all three apps in three lines

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

## Tests

```bash
go test -race ./...
cd bindings/python && python3 -m unittest
swift build
```

## Licence

MIT
