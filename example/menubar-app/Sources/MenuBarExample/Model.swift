import Foundation
import Vero

/// What this example is, in full: the types the two sides agree on.
///
/// There is no model class here any more, and that is the point. Holding the
/// worker, catching a launch that failed into something a view can show,
/// keeping the last event as published state, forwarding the client's changes
/// so a view redraws - every application wrote that, and each copy had its own
/// way of getting the last one subtly wrong. ``VeroModel`` is all of it, so
/// what is left is this file and a view.

struct Job: Decodable, Identifiable {
    let id: Int
    let name: String
    let phase: String
    let progress: Int

    var finished: Bool { phase == "done" }
}

/// Everything the interface draws, pushed whenever any of it moves.
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

/// The example ships a single universal worker; a real application would too,
/// so there is no architecture to choose.
var workerName: String {
    ProcessInfo.processInfo.environment["VERO_WORKER_NAME"] ?? "worker"
}
