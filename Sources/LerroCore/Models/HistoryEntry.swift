import Foundation

public enum HistoryStatus: String, Codable, Sendable {
    case completed
    case failed
    case cancelled
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
        audioRelativePath: String? = nil
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
