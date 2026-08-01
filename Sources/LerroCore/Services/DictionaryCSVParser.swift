import Foundation

public enum DictionaryCSVError: LocalizedError, Sendable, Equatable {
    case emptyFile
    case noEntries

    public var errorDescription: String? {
        switch self {
        case .emptyFile:
            "CSV 文件为空"
        case .noEntries:
            "CSV 文件中没有可导入的词条"
        }
    }
}

public enum DictionaryCSVParser {
    public static func parse(_ contents: String) throws -> [DictionaryEntry] {
        let rows = contents.split(whereSeparator: \.isNewline).map(String.init)
        guard !rows.isEmpty else { throw DictionaryCSVError.emptyFile }

        let firstRow = rows[0]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{feff}", with: "")
            .lowercased()
        let dataRows = firstRow.hasPrefix("phrase,") || firstRow == "phrase"
            ? rows.dropFirst()
            : rows[...]

        let entries = dataRows.compactMap { row -> DictionaryEntry? in
            let fields = row.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard let phrase = fields.first?.trimmingCharacters(in: .whitespacesAndNewlines), !phrase.isEmpty else {
                return nil
            }
            let replacement = fields.count > 1
                ? fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
                : phrase
            return DictionaryEntry(
                phrase: phrase,
                replacement: replacement.isEmpty ? phrase : replacement
            )
        }

        guard !entries.isEmpty else { throw DictionaryCSVError.noEntries }
        return entries
    }
}
