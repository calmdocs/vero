import SwiftUI
import Vero

@main
struct MenuBarExampleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: delegate.model)
        } label: {
            Image(systemName: delegate.model.working
                  ? "arrow.triangle.2.circlepath"
                  : "checkmark.circle")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = Model()

    private var recordingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()

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
            let hosting = NSHostingView(rootView: MenuView(model: model))
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
        model.stop()
    }
}

// MARK: - The menu

struct MenuView: View {
    @ObservedObject var model: Model

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if model.jobs.isEmpty {
                emptyState
            } else {
                // Not a ScrollView: inside a MenuBarExtra it has no height to
                // fill and collapses to nothing, taking the list with it. A
                // handful of rows sizes itself.
                VStack(spacing: 10) {
                    ForEach(model.jobs) { job in
                        JobCard(job: job) { model.restart(job) }
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
            Text("\(model.jobs.count) \(model.jobs.count == 1 ? "job" : "jobs")")
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
                .fill(model.worker?.state == .running ? Palette.done : Palette.warn)
                .frame(width: 7, height: 7)
            Text(model.worker?.state.rawValue ?? "starting")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let problem = model.problem {
                Text("· \(problem)")
                    .font(.caption)
                    .foregroundStyle(Palette.warn)
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
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 14) {
            // A button, not a picture. The platform draws it, and it behaves
            // the way a button on this platform behaves: hover, focus ring,
            // keyboard.
            Button(action: restart) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                    .frame(width: 34)
            }
            .buttonStyle(.borderless)
            .help("Restart")

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(job.name).font(.headline)
                    PhaseBadge(phase: job.phase)
                    Spacer()
                }

                if job.finished {
                    Text("Up to date")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressBar(fraction: Double(job.progress) / 100)
                }
            }

            if job.finished {
                Button(action: restart) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Start again")
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(hovered ? 0.12 : 0.05),
                        radius: hovered ? 5 : 2, y: 1)
        )
        .onHover { hovered = $0 }
    }

    private var icon: String {
        switch job.name {
        case "Photos":     return "photo.on.rectangle"
        case "Documents":  return "doc.text"
        case "Team share": return "person.2"
        default:           return "folder"
        }
    }
}

/// Drawn rather than using ProgressView.
///
/// A system progress bar renders in grey when its window is not the key one,
/// ignoring any tint, which is right for a form and wrong for a status display
/// that is meant to be glanced at from across the room.
struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(Palette.active)
                    .frame(width: max(3, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 6)
    }
}

/// The phase, as a word rather than a number: "uploading" says more about what
/// is happening than 62% does.
///
/// Colour carries meaning here rather than decorating. Ordinary progress is
/// neutral - "looking for changes" is not a warning and should not look like
/// one - and only finishing earns a colour. Reserving amber and red for things
/// that are actually wrong is what makes them worth noticing.
struct PhaseBadge: View {
    let phase: String

    var body: some View {
        Text(phase)
            .font(.caption2).fontWeight(.medium)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(colour.opacity(0.16)))
            .foregroundStyle(colour)
    }

    private var colour: Color {
        switch phase {
        case "done":      return Palette.done
        case "uploading": return Palette.active
        default:          return Palette.neutral
        }
    }
}

/// Muted on purpose. Saturated blue against saturated amber, on every row, is
/// loud enough to be tiring in something that sits in the menu bar all day.
enum Palette {
    static let neutral = Color(red: 0.58, green: 0.58, blue: 0.61)
    static let active  = Color(red: 0.36, green: 0.51, blue: 0.69)
    static let done    = Color(red: 0.36, green: 0.62, blue: 0.46)
    static let warn    = Color(red: 0.76, green: 0.55, blue: 0.29)
}
