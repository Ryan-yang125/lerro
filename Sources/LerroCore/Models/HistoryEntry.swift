import Foundation

public enum HistoryStatus: String, Codable, Sendable {
    case completed
    case failed
    case cancelled
    case undone
}

public enum HistoryProcessingRoute: String, Codable, Sendable {
    case raw
    case remote

    /// History files written by older versions may hold route names that no longer exist
    /// ("localSnippet", "local", "appleTranslation"). They decode as `.raw`.
    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .raw
    }
}

public enum HistoryContextCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case application
    case windowTitle
    case nearbyText
    case selectedText
    case dictionary
    case tone
}

public struct HistoryPhaseTimings: Codable, Equatable, Hashable, Sendable {
    public var recording: TimeInterval
    public var transcription: TimeInterval
    public var processing: TimeInterval
    public var delivery: TimeInterval
    /// Seconds from the hotkey press on the monotonic clock. Empty for
    /// entries saved before capture tracing existed.
    public var milestones: [CaptureMilestone: TimeInterval]
    public var outcome: CaptureTraceOutcome?

    public init(
        recording: TimeInterval,
        transcription: TimeInterval,
        processing: TimeInterval,
        delivery: TimeInterval,
        milestones: [CaptureMilestone: TimeInterval] = [:],
        outcome: CaptureTraceOutcome? = nil
    ) {
        self.recording = recording
        self.transcription = transcription
        self.processing = processing
        self.delivery = delivery
        self.milestones = milestones
        self.outcome = outcome
    }

    /// Snapshot of an open trace at history-save time.
    public init(trace: CaptureTrace, outcome: CaptureTraceOutcome) {
        self.init(
            recording: trace.duration(of: .recording) ?? 0,
            transcription: trace.duration(of: .transcription) ?? 0,
            processing: trace.duration(of: .processing) ?? 0,
            delivery: trace.duration(of: .delivery) ?? 0,
            milestones: trace.offsets,
            outcome: outcome
        )
    }

    public var total: TimeInterval {
        recording + transcription + processing + delivery
    }

    public func duration(of segment: CaptureTraceSegment) -> TimeInterval? {
        guard let from = milestones[segment.from], let to = milestones[segment.to] else { return nil }
        return to - from
    }

    private enum CodingKeys: String, CodingKey {
        case recording, transcription, processing, delivery, milestones, outcome
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recording = try container.decode(TimeInterval.self, forKey: .recording)
        transcription = try container.decode(TimeInterval.self, forKey: .transcription)
        processing = try container.decode(TimeInterval.self, forKey: .processing)
        delivery = try container.decode(TimeInterval.self, forKey: .delivery)
        let rawMilestones = try container.decodeIfPresent([String: TimeInterval].self, forKey: .milestones) ?? [:]
        milestones = Dictionary(uniqueKeysWithValues: rawMilestones.compactMap { key, value in
            CaptureMilestone(rawValue: key).map { ($0, value) }
        })
        outcome = try container.decodeIfPresent(String.self, forKey: .outcome)
            .flatMap(CaptureTraceOutcome.init(rawValue:))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(recording, forKey: .recording)
        try container.encode(transcription, forKey: .transcription)
        try container.encode(processing, forKey: .processing)
        try container.encode(delivery, forKey: .delivery)
        if !milestones.isEmpty {
            try container.encode(
                Dictionary(uniqueKeysWithValues: milestones.map { ($0.key.rawValue, $0.value) }),
                forKey: .milestones
            )
        }
        try container.encodeIfPresent(outcome, forKey: .outcome)
    }
}

public struct HistoryContextReceipt: Codable, Equatable, Hashable, Sendable {
    public var capturedCategories: Set<HistoryContextCategory>
    public var remoteSharedCategories: Set<HistoryContextCategory>

    public init(
        capturedCategories: Set<HistoryContextCategory> = [],
        remoteSharedCategories: Set<HistoryContextCategory> = []
    ) {
        self.capturedCategories = capturedCategories
        self.remoteSharedCategories = remoteSharedCategories
    }
}

public struct HistoryEntry: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var mode: CaptureMode
    public var rawText: String
    public var finalText: String
    public var answerText: String?
    public var targetLanguage: String?
    public var sourceLanguage: String?
    public var duration: TimeInterval
    public var applicationName: String
    public var bundleIdentifier: String?
    public var windowTitle: String?
    public var status: HistoryStatus
    public var wasEnhanced: Bool
    public var audioRelativePath: String?
    public var processedText: String?
    public var processingRoute: HistoryProcessingRoute?
    public var modelIdentifier: String?
    public var contextReceipt: HistoryContextReceipt?
    public var phaseTimings: HistoryPhaseTimings?
    public var aiCall: AICallTrace?

    public init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        mode: CaptureMode,
        rawText: String,
        finalText: String,
        answerText: String? = nil,
        targetLanguage: String? = nil,
        sourceLanguage: String? = nil,
        duration: TimeInterval,
        applicationName: String,
        bundleIdentifier: String? = nil,
        windowTitle: String? = nil,
        status: HistoryStatus = .completed,
        wasEnhanced: Bool = false,
        audioRelativePath: String? = nil,
        processedText: String? = nil,
        processingRoute: HistoryProcessingRoute? = nil,
        modelIdentifier: String? = nil,
        contextReceipt: HistoryContextReceipt? = nil,
        phaseTimings: HistoryPhaseTimings? = nil,
        aiCall: AICallTrace? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.mode = mode
        self.rawText = rawText
        self.finalText = finalText
        self.answerText = answerText
        self.targetLanguage = targetLanguage
        self.sourceLanguage = sourceLanguage
        self.duration = duration
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.status = status
        self.wasEnhanced = wasEnhanced
        self.audioRelativePath = audioRelativePath
        self.processedText = processedText
        self.processingRoute = processingRoute
        self.modelIdentifier = modelIdentifier
        self.contextReceipt = contextReceipt
        self.phaseTimings = phaseTimings
        self.aiCall = aiCall
    }
}

public struct UsageSummary: Equatable, Sendable {
    public var totalDuration: TimeInterval
    public var totalWords: Int
    public var savedSeconds: TimeInterval
    public var averageWordsPerMinute: Int

    public init(
        totalDuration: TimeInterval = 0,
        totalWords: Int = 0,
        savedSeconds: TimeInterval = 0,
        averageWordsPerMinute: Int = 0
    ) {
        self.totalDuration = totalDuration
        self.totalWords = totalWords
        self.savedSeconds = savedSeconds
        self.averageWordsPerMinute = averageWordsPerMinute
    }
}
