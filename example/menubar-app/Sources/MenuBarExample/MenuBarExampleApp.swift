import Combine
import SwiftUI
import Vero

@main
struct MenuBarExampleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuView(vero: delegate.vero)
        } label: {
            Image(systemName: delegate.vero.state?.working == true
                  ? "arrow.triangle.2.circlepath"
                  : "checkmark.circle")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    /// The worker, the last state it pushed, and everything a view needs to
    /// draw both.  Created here rather than when a view appears: a menu bar
    /// app may go a long time before anyone opens its panel, and the worker
    /// should be running before then.
    let vero = VeroModel<Status>(
        bundledWorker: workerName, directoryName: "VeroMenuBarExample/bin")

    private var recordingWindow: NSWindow?
    private var forwarding: AnyCancellable?

    /// ObservableObject, and forwarding, both for the menu bar label.
    ///
    /// @NSApplicationDelegateAdaptor only watches a delegate that is an
    /// ObservableObject, and an ObservableObject is not republished by one it
    /// holds - so without these two the icon reads `working` once, at launch,
    /// and never changes again.  The panel is fine either way, because it
    /// observes the model directly.
    override init() {
        super.init()
        forwarding = vero.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {

        // The same view in an ordinary window, for recording the screenshots
        // in the README. A MenuBarExtra panel closes the moment focus moves,
        // so it cannot be filmed, and its position moves with whatever else
        // is in the menu bar, so it cannot reliably be cropped either.
        //
        // A menu bar app runs as an accessory, which suppresses windows, so
        // this also has to ask for a normal activation policy.
        if ProcessInfo.processInfo.environment["VERO_EXAMPLE_WINDOW"] != nil {
            NSApp.setActivationPolicy(.regular)
            let window = NSWindow(
                contentRect: NSRect(x: 100, y: 100, width: 380, height: 350),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden

            // Size to the view. A fixed height leaves empty space below the
            // last card, which a MenuBarExtra panel never shows because it
            // sizes itself to its content.
            let hosting = NSHostingView(rootView: MenuView(vero: vero))
            hosting.sizingOptions = [.preferredContentSize]
            window.contentView = hosting
            window.setFrameOrigin(NSPoint(x: 100, y: 400))
            // Above everything else, or another window covers it between the
            // command that positions it and the one that records it.
            window.level = .floating
            window.makeKeyAndOrderFront(nil)
            recordingWindow = window
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Not required - the worker's stdin closes when we exit and it stops
        // with us, even if we crash - but it ends the work a moment sooner.
        vero.stop()
    }
}

// MARK: - The menu

struct MenuView: View {
    @ObservedObject var vero: VeroModel<Status>

    private var jobs: [Job] { vero.state?.jobs ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if jobs.isEmpty {
                emptyState
            } else {
                // Not a ScrollView: inside a MenuBarExtra it has no height to
                // fill and collapses to nothing, taking the list with it. A
                // handful of rows sizes itself.
                VStack(spacing: 10) {
                    ForEach(jobs) { job in
                        // No reply to handle: the worker pushes the new state,
                        // which is what redraws this.
                        JobCard(job: job) { vero.call(RestartJob(id: job.id)) }
                    }
                }
                .padding(16)
            }

            Divider()
            footer
        }
        .frame(width: 380)
    }

    private var header: some View {
        HStack {
            Text("vero")
                .font(.title2).fontWeight(.bold)
            Spacer()
            Text("\(jobs.count) \(jobs.count == 1 ? "job" : "jobs")")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text("Waiting for the worker")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            // Published by vero, so nothing here polls. Worth showing:
            // "restarting" and stale progress look identical otherwise.
            Circle()
                .fill(vero.workerState == .running ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(vero.workerState.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let problem = vero.problem {
                Text("· \(problem)")
                    .font(.caption)
                    .foregroundStyle(Color.orange)
                    .lineLimit(1)
            }

            Spacer()

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}

// MARK: - One job

struct JobCard: View {
    let job: Job
    let restart: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // A button, not a picture. The platform draws it, and it behaves
            // the way a button on this platform behaves: hover, focus ring,
            // keyboard.
            Button(action: restart) {
                Image(systemName: icon)
            }
            .help("Restart")

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(job.name)
                    Text(job.phase).foregroundStyle(.secondary)
                }
                ProgressView(value: Double(job.progress) / 100)
            }
        }
    }

    private var icon: String {
        switch job.name {
        case "Photos": return "photo.on.rectangle"
        case "Documents": return "doc.text"
        case "Team share": return "person.2"
        default: return "folder"
        }
    }
}
