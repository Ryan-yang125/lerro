import Foundation
import LerroCore
import OSLog
import Synchronization

/// Writes capture traces to the unified log and Instruments signposts.
/// Records only milestone names, durations, modes and error kinds.
public final class OSLogCaptureTraceObserver: CaptureTraceObserving {
    private enum Interval: CaseIterable {
        case capture
        case startup
        case recording
        case transcription
        case processing
        case delivery

        func begin(on signposter: OSSignposter, id: OSSignpostID) -> OSSignpostIntervalState {
            switch self {
            case .capture: signposter.beginInterval("Capture", id: id)
            case .startup: signposter.beginInterval("Startup", id: id)
            case .recording: signposter.beginInterval("Recording", id: id)
            case .transcription: signposter.beginInterval("Transcription", id: id)
            case .processing: signposter.beginInterval("Processing", id: id)
            case .delivery: signposter.beginInterval("Delivery", id: id)
            }
        }

        func end(on signposter: OSSignposter, state: OSSignpostIntervalState) {
            switch self {
            case .capture: signposter.endInterval("Capture", state)
            case .startup: signposter.endInterval("Startup", state)
            case .recording: signposter.endInterval("Recording", state)
            case .transcription: signposter.endInterval("Transcription", state)
            case .processing: signposter.endInterval("Processing", state)
            case .delivery: signposter.endInterval("Delivery", state)
            }
        }
    }

    private struct TraceState {
        let signpostID: OSSignpostID
        var openIntervals: [Interval: OSSignpostIntervalState] = [:]
    }

    private static let logger = Logger(subsystem: "app.lerro.mac", category: "capture-trace")

    private let signposter = OSSignposter(subsystem: "app.lerro.mac", category: .pointsOfInterest)
    private let traces = Mutex<[UUID: TraceState]>([:])

    public init() {}

    public func captureTraceDidBegin(_ trace: CaptureTrace) {
        let signpostID = signposter.makeSignpostID()
        var state = TraceState(signpostID: signpostID)
        state.openIntervals[.capture] = Interval.capture.begin(on: signposter, id: signpostID)
        state.openIntervals[.startup] = Interval.startup.begin(on: signposter, id: signpostID)
        traces.withLock { $0[trace.id] = state }
    }

    public func captureTrace(_ id: UUID, didMark milestone: CaptureMilestone, offset: TimeInterval) {
        let signpostID = traces.withLock { traces -> OSSignpostID in
            guard var state = traces[id] else { return .exclusive }
            switch milestone {
            case .listening:
                endInterval(.startup, in: &state)
                beginInterval(.recording, in: &state)
            case .stopRequested:
                endInterval(.recording, in: &state)
                beginInterval(.transcription, in: &state)
            case .transcriptionFinished:
                endInterval(.transcription, in: &state)
                beginInterval(.processing, in: &state)
            case .processingFinished:
                endInterval(.processing, in: &state)
                beginInterval(.delivery, in: &state)
            case .deliveryFinished:
                endInterval(.delivery, in: &state)
            default:
                break
            }
            traces[id] = state
            return state.signpostID
        }
        signposter.emitEvent("Milestone", id: signpostID, "\(milestone.rawValue, privacy: .public)")
        let shortID = Self.shortID(of: id)
        let milliseconds = Self.milliseconds(offset)
        Self.logger.debug(
            "capture \(shortID, privacy: .public) \(milestone.rawValue, privacy: .public) +\(milliseconds, privacy: .public)ms"
        )
    }

    public func captureTraceDidFinish(_ trace: CaptureTrace) {
        let state = traces.withLock { $0.removeValue(forKey: trace.id) }
        if let state {
            for interval in Interval.allCases {
                if let intervalState = state.openIntervals[interval] {
                    interval.end(on: signposter, state: intervalState)
                }
            }
        }
        let summary = Self.summaryLine(for: trace)
        let steps = Self.stepsLine(for: trace)
        Self.logger.notice("\(summary, privacy: .public)")
        Self.logger.notice("\(steps, privacy: .public)")
    }

    public func dictionaryLearningDidClassify(duration: TimeInterval, candidateCount: Int, savedCount: Int) {
        let milliseconds = Self.milliseconds(duration)
        Self.logger.notice(
            "dictionary-learning classify=\(milliseconds, privacy: .public)ms candidates=\(candidateCount, privacy: .public) saved=\(savedCount, privacy: .public)"
        )
    }

    static func summaryLine(for trace: CaptureTrace) -> String {
        var parts = [
            "capture \(shortID(of: trace.id))",
            "mode=\(trace.mode.rawValue)",
            "intelligence=\(trace.intelligenceMode.rawValue)",
            "route=\(trace.processingRoute?.rawValue ?? "-")",
            "outcome=\(trace.outcome?.rawValue ?? "-")",
            "last=\(trace.lastReachedMilestone?.rawValue ?? "-")",
            "error=\(trace.errorKind ?? "-")"
        ]
        for segment in CaptureTraceSegment.summaries {
            if let duration = trace.duration(of: segment) {
                parts.append("\(segment.name)=\(milliseconds(duration))ms")
            }
        }
        return parts.joined(separator: " ")
    }

    static func stepsLine(for trace: CaptureTrace) -> String {
        var parts = ["capture \(shortID(of: trace.id)) steps"]
        for segment in CaptureTraceSegment.steps {
            if let duration = trace.duration(of: segment) {
                parts.append("\(segment.name)=\(milliseconds(duration))ms")
            }
        }
        return parts.joined(separator: " ")
    }

    private func beginInterval(_ interval: Interval, in state: inout TraceState) {
        guard state.openIntervals[interval] == nil else { return }
        state.openIntervals[interval] = interval.begin(on: signposter, id: state.signpostID)
    }

    private func endInterval(_ interval: Interval, in state: inout TraceState) {
        guard let intervalState = state.openIntervals.removeValue(forKey: interval) else { return }
        interval.end(on: signposter, state: intervalState)
    }

    private static func shortID(of id: UUID) -> String {
        String(id.uuidString.lowercased().prefix(8))
    }

    private static func milliseconds(_ seconds: TimeInterval) -> Int {
        Int((seconds * 1_000).rounded())
    }
}
