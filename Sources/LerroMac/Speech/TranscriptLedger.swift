import Foundation

struct TranscriptLedger: Sendable, Equatable {
    private var segments: [Segment] = []

    mutating func apply(
        text: String,
        start: Double,
        duration: Double,
        isFinal: Bool
    ) {
        let range = Range(start: start, duration: duration)
        if isFinal {
            segments.removeAll { $0.range.overlaps(range) }
            if !text.isEmpty { segments.append(Segment(range: range, text: text, isFinal: true)) }
        } else {
            // Empty volatile results retract speculative text for their range.
            segments.removeAll { !$0.isFinal && $0.range.overlaps(range) }
            if !text.isEmpty { segments.append(Segment(range: range, text: text, isFinal: false)) }
        }
    }

    var composedText: String {
        segments.sorted { lhs, rhs in
            lhs.range.start == rhs.range.start
                ? lhs.range.duration < rhs.range.duration
                : lhs.range.start < rhs.range.start
        }.reduce("") { partial, segment in
            guard !partial.isEmpty else { return segment.text }
            return partial + transcriptSeparator(after: partial, before: segment.text) + segment.text
        }
    }

    private struct Segment: Sendable, Equatable {
        let range: Range
        let text: String
        let isFinal: Bool
    }

    private struct Range: Sendable, Equatable {
        let start: Double
        let duration: Double

        func overlaps(_ other: Range) -> Bool {
            let end = start + duration
            let otherEnd = other.start + other.duration
            if duration == 0 || other.duration == 0 { return abs(start - other.start) < 0.05 }
            return start < otherEnd && other.start < end
        }
    }
}
