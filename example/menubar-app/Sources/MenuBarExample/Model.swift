import Foundation
import SwiftUI
import Vero

struct Job: Decodable, Identifiable {
    let id: Int
    let name: String
    let phase: String
    let progress: Int

    var finished: Bool { phase == "done" }
}

struct Status: Decodable {
    let jobs: [Job]
    let working: Bool
    let since: String
}

/// The requests this interface makes.  Each names the handler on the worker it
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

/// Everything this example needs to drive a Go worker.
///
/// Note what is not here: no in-flight counting, no retry policy, no polling
/// for the worker's state, no copying the worker out of the bundle, no
/// deciding whether the copy on disk is newer. VeroClient does all of it, and
/// each one is somewhere an application would otherwise get it subtly wrong.
@MainActor
final class Model: ObservableObject {
    @Published var jobs: [Job] = []
    @Published var working = false
    @Published var problem: String?

    /// The worker. Published so views can read `worker.isBusy` and
    /// `worker.state` directly.
    @Published private(set) var worker: VeroClient?

    func start() {
        do {
            // Copies the worker out of the bundle if the copy on disk is
            // missing, unusable or older, then launches and supervises it.
            let worker = try VeroClient(
                bundledWorker: workerName,
                directoryName: "VeroMenuBarExample/bin")

            // A worker that keeps dying is one whose file is suspect, so put
            // the shipped copy back before giving up on it.
            worker.restoreBundledWorkerAfterRepeatedRestarts(3) { [weak self] in
                self?.problem = "The worker keeps stopping. Try reinstalling."
            }

            // Pushed the instant anything changes, already on the main actor.
            worker.onEvent(Status.self) { [weak self] status in
                self?.apply(status)
            }
            if let status = worker.latest(Status.self) { apply(status) }

            self.worker = worker
        } catch {
            problem = "Could not start the worker: \(error.localizedDescription)"
        }
    }

    func restart(_ job: Job) {
        // `then` runs when the reply has arrived: asking for the list at the
        // same moment as changing it can return the list from before.
        worker?.call(RestartJob(id: job.id)) { [weak self] in
            self?.refresh()
        }
    }

    func refresh() {
        guard let worker else { return }
        Task {
            do {
                apply(try await worker.call(StatusRequest()))
            } catch VeroError.refused(let message) {
                // The worker got it and said no. It is still there, so this is
                // worth showing; "not running" would not be.
                problem = message
            } catch {
                // notRunning is already visible through worker.state.
            }
        }
    }

    func stop() { worker?.stop() }

    private func apply(_ status: Status) {
        jobs = status.jobs
        working = status.working
        problem = nil
    }

    /// The example ships a single universal worker; a real application would
    /// too, so there is no architecture to choose.
    private var workerName: String {
        ProcessInfo.processInfo.environment["VERO_WORKER_NAME"] ?? "worker"
    }
}
