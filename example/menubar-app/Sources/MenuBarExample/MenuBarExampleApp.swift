import Foundation
import SwiftUI
import Vero

/// The whole frontend, in one file: the types the two sides agree on, the
/// requests this app makes, and the views that draw the result.
///
/// There is no model class here, and that is the point. Holding the worker,
/// catching a launch that failed into something a view can show, keeping the
/// last event as published state, forwarding the client's changes so a view
/// redraws - every application wrote that, and each copy had its own way of
/// getting the last one subtly wrong. ``VeroModel`` is all of it, so what is
/// left is the types below and the views underneath them.

// MARK: - What the worker sends

struct Job: Decodable, Identifiable {
    let id: Int
    let name: String
    let phase: String
    let progress: Int

    var finished: Bool { phase == "done" }
}

/// Everything the frontend draws, pushed whenever any of it moves.
///
/// One type rather than an event per subject: the event channel carries no
/// name, so a second type would be told apart only by whichever decode
/// happened to succeed, and `latest` - a single slot - would hold whichever
/// arrived last. Widen this instead.
struct Status: Decodable {
    let jobs: [Job]
    let working: Bool
    let since: String
}

// MARK: - What this frontend asks for

/// The requests this frontend makes.  Each names the handler on the worker it
/// is routed to - matching vero.Handle over there - and declares what comes
/// back, so nothing has to guess at the reply.
struct StatusRequest: NamedRequest {
    static let name = "status"
    typealias Reply = Status
}

struct RestartJob: NamedRequest {
    static let name = "restartJob"
    typealias Reply = Status
    let id: Int
}

/// The example ships a single universal worker; a real application would too,
/// so there is no architecture to choose.
var workerName: String {
    ProcessInfo.processInfo.environment["VERO_WORKER_NAME"] ?? "worker"
}

// MARK: - The app

/// The worker, the last state it pushed, and everything a view needs to draw
/// both.
///
/// Named here rather than written straight into the `@StateObject` below only
/// because the screenshot window wants the same instance as the panel.  An
/// app without one writes the initialiser inline, as the README does.
@MainActor let veroModel = VeroModel<Status>(
    bundledWorker: workerName, directoryName: "VeroMenuBarExample/bin")

@main
struct MenuBarExampleApp: App {
    /// Held by the App, not by a view: a `@StateObject` here is created when
    /// the scene tree is built, at launch, so the worker is running long
    /// before anyone opens the panel.  Observing it here is also what keeps
    /// the menu bar icon current - the whole scene redraws when the worker
    /// pushes, so nothing has to forward the change by hand.
    @StateObject private var vero = veroModel

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuView(vero: vero)
        } label: {
            Image(systemName: vero.state?.working == true
                  ? "arrow.triangle.2.circlepath"
                  : "checkmark.circle")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Two jobs, neither of them vero's: the window the README's screenshots are
/// recorded in, and ending the worker a moment sooner on quit.  An app that
/// wants neither has no delegate at all.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var recordingWindow: NSWindow?

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
            let hosting = NSHostingView(rootView: MenuView(vero: veroModel))
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
        veroModel.stop()
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
