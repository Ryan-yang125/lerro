import Foundation

/// What a remote model call was made for.
public enum AIUsageFeature: String, Codable, CaseIterable, Hashable, Sendable {
    case dictate
    case translate
    case dictionaryLearning
    case tonePreview
    case connectionTest
}

/// Token counts reported by an OpenAI-compatible `usage` object.
/// `inputTokens` includes `cachedInputTokens`.
public struct AITokenUsage: Codable, Hashable, Sendable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var cachedInputTokens: Int

    public init(inputTokens: Int, outputTokens: Int, cachedInputTokens: Int = 0) {
        self.inputTokens = max(0, inputTokens)
        self.outputTokens = max(0, outputTokens)
        self.cachedInputTokens = min(max(0, cachedInputTokens), self.inputTokens)
    }

    public var totalTokens: Int { inputTokens + outputTokens }
}

/// One remote model call. Holds numbers and identifiers only: no transcript,
/// prompt, model output, context text or credential.
public struct AIUsageRecord: Codable, Hashable, Sendable, Identifiable {
    /// Records older than this are pruned on write.
    public static let retentionDays = 90

    public var id: UUID
    public var date: Date
    public var feature: AIUsageFeature
    public var provider: RemoteProviderKind
    public var modelIdentifier: String
    /// Nil when the call failed or the provider returned no `usage`.
    public var tokens: AITokenUsage?
    public var latencyMilliseconds: Int
    public var succeeded: Bool

    public init(
        id: UUID = UUID(),
        date: Date,
        feature: AIUsageFeature,
        provider: RemoteProviderKind,
        modelIdentifier: String,
        tokens: AITokenUsage?,
        latencyMilliseconds: Int,
        succeeded: Bool
    ) {
        self.id = id
        self.date = date
        self.feature = feature
        self.provider = provider
        self.modelIdentifier = modelIdentifier
        self.tokens = tokens
        self.latencyMilliseconds = max(0, latencyMilliseconds)
        self.succeeded = succeeded
    }
}

public protocol AIUsageRepository: Sendable {
    /// Appends a record and prunes records older than `AIUsageRecord.retentionDays`.
    func append(_ record: AIUsageRecord) async throws
    /// Records with `date >= since`, oldest first.
    func records(since: Date) async throws -> [AIUsageRecord]
    func deleteAll() async throws
}

public enum AIUsageCurrency: String, Codable, CaseIterable, Hashable, Sendable {
    case cny
    case usd

    public var symbol: String {
        switch self {
        case .cny: "¥"
        case .usd: "$"
        }
    }
}

/// Price of one model per one million tokens.
public struct AIModelPrice: Codable, Hashable, Sendable, Identifiable {
    public var modelIdentifier: String
    public var currency: AIUsageCurrency
    public var inputPerMillion: Double
    public var cachedInputPerMillion: Double
    public var outputPerMillion: Double
    /// Multiplier applied outside DeepSeek peak hours. Nil for flat pricing.
    public var offPeakFactor: Double?

    public init(
        modelIdentifier: String,
        currency: AIUsageCurrency,
        inputPerMillion: Double,
        cachedInputPerMillion: Double,
        outputPerMillion: Double,
        offPeakFactor: Double? = nil
    ) {
        self.modelIdentifier = modelIdentifier
        self.currency = currency
        self.inputPerMillion = max(0, inputPerMillion)
        self.cachedInputPerMillion = max(0, cachedInputPerMillion)
        self.outputPerMillion = max(0, outputPerMillion)
        self.offPeakFactor = offPeakFactor
    }

    public var id: String { modelIdentifier.lowercased() }

    /// DeepSeek list prices at peak hours, CNY, checked 2026-10-17 at
    /// https://api-docs.deepseek.com/zh-cn/quick_start/pricing. Off-peak is half.
    public static let builtIn: [AIModelPrice] = [
        AIModelPrice(
            modelIdentifier: "deepseek-flash",
            currency: .cny,
            inputPerMillion: 2,
            cachedInputPerMillion: 0.04,
            outputPerMillion: 8,
            offPeakFactor: 0.5
        ),
        // Retired ID that DeepSeek routes to deepseek-flash; older saved configs still use it.
        AIModelPrice(
            modelIdentifier: "deepseek-v4-flash",
            currency: .cny,
            inputPerMillion: 2,
            cachedInputPerMillion: 0.04,
            outputPerMillion: 8,
            offPeakFactor: 0.5
        ),
        AIModelPrice(
            modelIdentifier: "deepseek-v4-pro",
            currency: .cny,
            inputPerMillion: 9,
            cachedInputPerMillion: 0.3,
            outputPerMillion: 27,
            offPeakFactor: 0.5
        )
    ]

    public func cost(of tokens: AITokenUsage, at date: Date) -> Double {
        let uncached = Double(tokens.inputTokens - tokens.cachedInputTokens)
        let base = (uncached * inputPerMillion
            + Double(tokens.cachedInputTokens) * cachedInputPerMillion
            + Double(tokens.outputTokens) * outputPerMillion) / 1_000_000
        guard let offPeakFactor, !Self.isDeepSeekPeak(date) else { return base }
        return base * offPeakFactor
    }

    /// Monday to Friday, 9:00–12:00 and 14:00–18:00 Beijing time. Public
    /// holidays are treated as peak, so estimates err high.
    public static func isDeepSeekPeak(_ date: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
        let parts = calendar.dateComponents([.weekday, .hour], from: date)
        guard let weekday = parts.weekday, let hour = parts.hour else { return true }
        guard (2...6).contains(weekday) else { return false }
        return (9..<12).contains(hour) || (14..<18).contains(hour)
    }
}

/// User overrides take precedence over built-in prices. Matching ignores case.
public struct AIModelPriceTable: Sendable {
    public let overrides: [AIModelPrice]

    public init(overrides: [AIModelPrice]) {
        self.overrides = overrides
    }

    public func price(for modelIdentifier: String) -> AIModelPrice? {
        let key = modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return overrides.first { $0.id == key } ?? AIModelPrice.builtIn.first { $0.id == key }
    }

    public func builtInPrice(for modelIdentifier: String) -> AIModelPrice? {
        let key = modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return AIModelPrice.builtIn.first { $0.id == key }
    }
}

public struct AIUsageTotals: Hashable, Sendable {
    public var requests = 0
    public var failedRequests = 0
    public var inputTokens = 0
    public var outputTokens = 0
    public var cachedInputTokens = 0
    public var costs: [AIUsageCurrency: Double] = [:]
    /// Successful requests whose tokens could not be priced.
    public var unpricedRequests = 0

    public init() {}

    public var totalTokens: Int { inputTokens + outputTokens }

    mutating func add(_ record: AIUsageRecord, price: AIModelPrice?) {
        requests += 1
        if !record.succeeded { failedRequests += 1 }
        guard let tokens = record.tokens else { return }
        inputTokens += tokens.inputTokens
        outputTokens += tokens.outputTokens
        cachedInputTokens += tokens.cachedInputTokens
        if let price {
            costs[price.currency, default: 0] += price.cost(of: tokens, at: record.date)
        } else if tokens.totalTokens > 0 {
            unpricedRequests += 1
        }
    }
}

public struct AIUsageDay: Hashable, Sendable, Identifiable {
    public var day: Date
    public var totals: AIUsageTotals
    public var id: Date { day }
}

public struct AIUsageFeatureBreakdown: Hashable, Sendable, Identifiable {
    public var feature: AIUsageFeature
    public var totals: AIUsageTotals
    public var id: AIUsageFeature { feature }
}

public struct AIUsageModelBreakdown: Hashable, Sendable, Identifiable {
    public var modelIdentifier: String
    public var provider: RemoteProviderKind
    public var totals: AIUsageTotals
    public var id: String { modelIdentifier.lowercased() }
}

public struct AIUsageReport: Hashable, Sendable {
    public var totals: AIUsageTotals
    /// One entry per calendar day in the range, oldest first, including empty days.
    public var daily: [AIUsageDay]
    /// Features with at least one request, most tokens first.
    public var byFeature: [AIUsageFeatureBreakdown]
    /// Models with at least one request, most tokens first.
    public var byModel: [AIUsageModelBreakdown]
}

public enum AIUsageStatistics {
    /// Start of the range covering `days` calendar days ending today.
    public static func rangeStart(days: Int, now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: today) ?? today
    }

    public static func report(
        records: [AIUsageRecord],
        prices: AIModelPriceTable,
        days: Int,
        now: Date,
        calendar: Calendar = .current
    ) -> AIUsageReport {
        let start = rangeStart(days: days, now: now, calendar: calendar)
        let inRange = records.filter { $0.date >= start && $0.date <= now }

        var totals = AIUsageTotals()
        var byDay: [Date: AIUsageTotals] = [:]
        var byFeature: [AIUsageFeature: AIUsageTotals] = [:]
        var byModel: [String: (identifier: String, provider: RemoteProviderKind, totals: AIUsageTotals)] = [:]

        for record in inRange {
            let price = prices.price(for: record.modelIdentifier)
            totals.add(record, price: price)
            byDay[calendar.startOfDay(for: record.date), default: AIUsageTotals()].add(record, price: price)
            byFeature[record.feature, default: AIUsageTotals()].add(record, price: price)
            let key = record.modelIdentifier.lowercased()
            var model = byModel[key] ?? (record.modelIdentifier, record.provider, AIUsageTotals())
            model.totals.add(record, price: price)
            byModel[key] = model
        }

        let daily = (0..<max(1, days)).compactMap { offset -> AIUsageDay? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return AIUsageDay(day: day, totals: byDay[day] ?? AIUsageTotals())
        }

        return AIUsageReport(
            totals: totals,
            daily: daily,
            byFeature: byFeature
                .map { AIUsageFeatureBreakdown(feature: $0.key, totals: $0.value) }
                .sorted { ($0.totals.totalTokens, $1.feature.rawValue) > ($1.totals.totalTokens, $0.feature.rawValue) },
            byModel: byModel.values
                .map { AIUsageModelBreakdown(modelIdentifier: $0.identifier, provider: $0.provider, totals: $0.totals) }
                .sorted { ($0.totals.totalTokens, $1.modelIdentifier) > ($1.totals.totalTokens, $0.modelIdentifier) }
        )
    }
}
