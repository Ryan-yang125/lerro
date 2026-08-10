import Foundation

public enum HistoryStatus: String, Codable, Sendable {
    case completed
    case failed
    case cancelled
    case undone
}

public enum HistoryProcessingRoute: String, Codable, Sendable {
    case raw
    case local
    case remote
    case appleTranslation
    case localSnippet
}

public enum HistoryFinishAction: String, Codable, Sendable {
    case requested
    case submitted
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

    public init(
        recording: TimeInterval,
        transcription: TimeInterval,
        processing: TimeInterval,
        delivery: TimeInterval
    ) {
        self.recording = recording
        self.transcription = transcription
        self.processing = processing
        self.delivery = delivery
    }

    public var total: TimeInterval {
        recording + transcription + processing + delivery
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
    public var finishAction: HistoryFinishAction?

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
        finishAction: HistoryFinishAction? = nil
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
        self.finishAction = finishAction
    }

    public var wordCount: Int {
        finalText.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).count
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
