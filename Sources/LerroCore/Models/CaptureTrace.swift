import Foundation

/// Milestones of one capture, in chain order. Raw values are persisted in
/// history and read by `script/capture_latency_report.py`.
public enum CaptureMilestone: String, Codable, CaseIterable, Sendable {
    // Startup chain: physical key press until the microphone is capturing.
    case hotkeyPressed
    case hotkeyHandled
    case hudArmed
    case permissionsChecked
    case hotkeysConfigured
    case contextCaptured
    case speechResourcesReady
    case speechStartRequested
    case speechLocaleResolved
    case audioEngineCreated
    case audioInputConfigured
    case audioEngineStarted
    case listening

    // Analyzer chain: runs after the microphone opens while audio is buffered.
    case speechAssetsReserved
    case audioFormatNegotiated
    case analyzerCreated
    case analyzerPrepared

    // Live signals after the microphone opens.
    case firstAudioBuffer
    case firstPartial

    // Finish chain: stop gesture through the end of the interaction.
    case stopRequested
    case transcriptionFinished
    case processingFinished
    case deliveryCommitted
    case deliveryFinished
    case historySaved
    case finished

    public static let startupChain: [CaptureMilestone] = [
        .hotkeyPressed, .hotkeyHandled, .hudArmed, .permissionsChecked, .hotkeysConfigured,
        .contextCaptured, .speechResourcesReady, .speechStartRequested, .speechLocaleResolved,
        .audioEngineCreated, .audioInputConfigured, .audioEngineStarted, .listening
    ]

    /// Analyzer preparation, which starts once the microphone is capturing.
    public static let analyzerChain: [CaptureMilestone] = [
        .audioEngineStarted, .speechAssetsReserved, .audioFormatNegotiated, .analyzerCreated,
        .analyzerPrepared
    ]

    public static let finishChain: [CaptureMilestone] = [
        .stopRequested, .transcriptionFinished, .processingFinished, .deliveryCommitted,
        .deliveryFinished, .historySaved, .finished
    ]
}

public enum CaptureTraceOutcome: String, Codable, Sendable {
    case completed
    /// AI Dictate failed and the raw transcript was delivered.
    case completedWithRawFallback
    case deliveryFailed
    case failed
    case cancelled
}

/// A named duration between two milestones.
public struct CaptureTraceSegment: Hashable, Sendable {
    public let name: String
    public let from: CaptureMilestone
    public let to: CaptureMilestone

    public init(name: String, from: CaptureMilestone, to: CaptureMilestone) {
        self.name = name
        self.from = from
        self.to = to
    }

    /// Key press until the HUD waveform is live and speech is captured.
    public static let readyToSpeak = Self(name: "readyToSpeak", from: .hotkeyPressed, to: .listening)
    public static let hotkeyDispatch = Self(name: "hotkeyDispatch", from: .hotkeyPressed, to: .hotkeyHandled)
    public static let appPreparation = Self(name: "appPreparation", from: .hotkeyHandled, to: .speechStartRequested)
    public static let speechStartup = Self(name: "speechStartup", from: .speechStartRequested, to: .listening)
    /// Microphone open until the analyzer accepts the buffered audio.
    public static let analyzerStartup = Self(name: "analyzerStartup", from: .audioEngineStarted, to: .analyzerPrepared)
    public static let firstAudio = Self(name: "firstAudio", from: .hotkeyPressed, to: .firstAudioBuffer)
    public static let firstPartial = Self(name: "firstPartial", from: .hotkeyPressed, to: .firstPartial)
    public static let recording = Self(name: "recording", from: .listening, to: .stopRequested)
    public static let transcription = Self(name: "transcription", from: .stopRequested, to: .transcriptionFinished)
    public static let processing = Self(name: "processing", from: .transcriptionFinished, to: .processingFinished)
    public static let delivery = Self(name: "delivery", from: .processingFinished, to: .deliveryFinished)
    public static let stopToDelivered = Self(name: "stopToDelivered", from: .stopRequested, to: .deliveryCommitted)

    public static let summaries: [Self] = [
        .readyToSpeak, .hotkeyDispatch, .appPreparation, .speechStartup, .analyzerStartup,
        .firstAudio, .firstPartial,
        .recording, .transcription, .processing, .delivery, .stopToDelivered
    ]

    /// Every adjacent pair of the startup, analyzer and finish chains, named `from>to`.
    public static let steps: [Self] = [
        CaptureMilestone.startupChain, CaptureMilestone.analyzerChain, CaptureMilestone.finishChain
    ].flatMap { chain in
        zip(chain, chain.dropFirst()).map { from, to in
            Self(name: "\(from.rawValue)>\(to.rawValue)", from: from, to: to)
        }
    }
}

/// Monotonic timeline of one capture generation. The first mark of each
/// milestone wins, and a finished trace accepts no further marks.
public struct CaptureTrace: Equatable, Sendable {
    public let id: UUID
    public let mode: CaptureMode
    public let intelligenceMode: IntelligenceMode
    public let origin: ContinuousClock.Instant
    public private(set) var instants: [CaptureMilestone: ContinuousClock.Instant]
    public private(set) var outcome: CaptureTraceOutcome?
    public private(set) var errorKind: String?
    public var processingRoute: HistoryProcessingRoute?

    public init(
        id: UUID,
        mode: CaptureMode,
        intelligenceMode: IntelligenceMode,
        pressedAt: ContinuousClock.Instant,
        handledAt: ContinuousClock.Instant
    ) {
        self.id = id
        self.mode = mode
        self.intelligenceMode = intelligenceMode
        self.origin = pressedAt
        self.instants = [.hotkeyPressed: pressedAt, .hotkeyHandled: max(pressedAt, handledAt)]
    }

    public var isFinished: Bool { outcome != nil }

    @discardableResult
    public mutating func mark(_ milestone: CaptureMilestone, at instant: ContinuousClock.Instant) -> Bool {
        guard !isFinished, milestone != .finished, instants[milestone] == nil else { return false }
        instants[milestone] = instant
        return true
    }

    @discardableResult
    public mutating func finish(
        _ outcome: CaptureTraceOutcome,
        errorKind: String? = nil,
        at instant: ContinuousClock.Instant
    ) -> Bool {
        guard !isFinished else { return false }
        self.outcome = outcome
        self.errorKind = errorKind
        instants[.finished] = instant
        return true
    }

    /// Seconds since the hotkey press.
    public func offset(of milestone: CaptureMilestone) -> TimeInterval? {
        instants[milestone].map { origin.duration(to: $0).timeInterval }
    }

    public var offsets: [CaptureMilestone: TimeInterval] {
        instants.mapValues { origin.duration(to: $0).timeInterval }
    }

    public func duration(of segment: CaptureTraceSegment) -> TimeInterval? {
        guard let from = instants[segment.from], let to = instants[segment.to] else { return nil }
        return from.duration(to: to).timeInterval
    }

    /// The latest milestone reached before the trace finished.
    public var lastReachedMilestone: CaptureMilestone? {
        instants
            .filter { $0.key != .finished }
            .max { $0.value < $1.value }?
            .key
    }

    /// A payload-free name for an error, safe for logs.
    public static func errorKind(of error: any Error) -> String {
        if error is CancellationError { return "cancelled" }
        if let lerroError = error as? LerroError {
            return Mirror(reflecting: lerroError).children.first?.label ?? "\(lerroError)"
        }
        return String(describing: type(of: error))
    }
}

/// Owns the trace of the current capture generation. Marks and finishes for
/// any other generation are ignored, so stale async work cannot touch a new
/// capture's timeline.
public struct CaptureTraceRecorder: Sendable {
    public private(set) var current: CaptureTrace?

    public init() {}

    /// Starts a trace and returns the previous one if it was still open.
    @discardableResult
    public mutating func begin(_ trace: CaptureTrace) -> CaptureTrace? {
        let superseded = current.flatMap { $0.isFinished ? nil : $0 }
        current = trace
        return superseded
    }

    @discardableResult
    public mutating func mark(
        _ milestone: CaptureMilestone,
        id: UUID,
        at instant: ContinuousClock.Instant
    ) -> Bool {
        guard current?.id == id else { return false }
        return current?.mark(milestone, at: instant) ?? false
    }

    public mutating func setProcessingRoute(_ route: HistoryProcessingRoute, id: UUID) {
        guard current?.id == id, current?.isFinished == false else { return }
        current?.processingRoute = route
    }

    /// Finishes the current trace once and returns it. Later calls return nil.
    public mutating func finish(
        _ outcome: CaptureTraceOutcome,
        errorKind: String? = nil,
        at instant: ContinuousClock.Instant
    ) -> CaptureTrace? {
        guard var trace = current, trace.finish(outcome, errorKind: errorKind, at: instant) else {
            return nil
        }
        current = nil
        return trace
    }
}

/// Speech adapters report startup milestones with the instant they happened.
public typealias CaptureMilestoneReporter = @Sendable (CaptureMilestone, ContinuousClock.Instant) -> Void

/// Receives live trace events on the MainActor. Implementations must not
/// record transcripts, context text, prompts, model output or credentials.
public protocol CaptureTraceObserving: Sendable {
    func captureTraceDidBegin(_ trace: CaptureTrace)
    func captureTrace(_ id: UUID, didMark milestone: CaptureMilestone, offset: TimeInterval)
    func captureTraceDidFinish(_ trace: CaptureTrace)
    func dictionaryLearningDidClassify(duration: TimeInterval, candidateCount: Int, savedCount: Int)
}

public struct DiscardingCaptureTraceObserver: CaptureTraceObserving {
    public init() {}
    public func captureTraceDidBegin(_ trace: CaptureTrace) {}
    public func captureTrace(_ id: UUID, didMark milestone: CaptureMilestone, offset: TimeInterval) {}
    public func captureTraceDidFinish(_ trace: CaptureTrace) {}
    public func dictionaryLearningDidClassify(duration: TimeInterval, candidateCount: Int, savedCount: Int) {}
}

public extension Duration {
    var timeInterval: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1_000_000_000_000_000_000
    }
}
