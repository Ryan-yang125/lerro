import Foundation

public enum DeterministicVoiceEditCommand: Codable, Equatable, Hashable, Sendable {
    case undo
    case deleteSentence(Int)
    case replaceExact(source: String, replacement: String)
    case redictate
}

public enum SemanticVoiceEditOperation: String, Codable, Equatable, Hashable, Sendable {
    case shorten
    case expand
    case changeTone
    case translate
    case general
}

public struct SemanticVoiceEditRequest: Codable, Equatable, Hashable, Sendable {
    public var operation: SemanticVoiceEditOperation
    public var instruction: String

    public init(operation: SemanticVoiceEditOperation, instruction: String) {
        self.operation = operation
        self.instruction = instruction
    }
}

public enum VoiceEditRequest: Codable, Equatable, Hashable, Sendable {
    case deterministic(DeterministicVoiceEditCommand)
    case semantic(SemanticVoiceEditRequest)
}

public enum DeliveryEditVersionOrigin: String, Codable, Equatable, Hashable, Sendable {
    case original
    case manual
    case deterministic
    case semantic
    case redictation
}

public struct DeliveryEditVersion: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var parentID: UUID?
    public var createdAt: Date
    public var text: String
    public var origin: DeliveryEditVersionOrigin
    public var instruction: String?
    public var modelIdentifier: String?
    public var processingRoute: HistoryProcessingRoute?

    public init(
        id: UUID = UUID(),
        parentID: UUID?,
        createdAt: Date = .now,
        text: String,
        origin: DeliveryEditVersionOrigin,
        instruction: String? = nil,
        modelIdentifier: String? = nil,
        processingRoute: HistoryProcessingRoute? = nil
    ) {
        self.id = id
        self.parentID = parentID
        self.createdAt = createdAt
        self.text = text
        self.origin = origin
        self.instruction = instruction
        self.modelIdentifier = modelIdentifier
        self.processingRoute = processingRoute
    }
}

public enum DeliveryEditLineageError: Error, Equatable, Sendable {
    case emptyText
    case invalidOrigin
    case duplicateVersionID
    case missingCurrentVersion
}

/// An append-only delivery edit history. `currentVersionID` may move backwards
/// while every prior branch remains available for history and diagnostics.
public struct DeliveryEditLineage: Codable, Equatable, Hashable, Sendable {
    public private(set) var versions: [DeliveryEditVersion]
    public private(set) var currentVersionID: UUID

    public init(
        originalText: String,
        versionID: UUID = UUID(),
        createdAt: Date = .now
    ) throws {
        let text = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw DeliveryEditLineageError.emptyText }
        let original = DeliveryEditVersion(
            id: versionID,
            parentID: nil,
            createdAt: createdAt,
            text: originalText,
            origin: .original
        )
        self.versions = [original]
        self.currentVersionID = versionID
    }

    public var currentVersion: DeliveryEditVersion? {
        versions.first { $0.id == currentVersionID }
    }

    public var canUndo: Bool {
        currentVersion?.parentID != nil
    }

    public var currentPath: [DeliveryEditVersion] {
        var path: [DeliveryEditVersion] = []
        var nextID: UUID? = currentVersionID
        var visited: Set<UUID> = []
        while let id = nextID,
              visited.insert(id).inserted,
              let version = versions.first(where: { $0.id == id }) {
            path.append(version)
            nextID = version.parentID
        }
        return path.reversed()
    }

    @discardableResult
    public mutating func append(
        text: String,
        origin: DeliveryEditVersionOrigin,
        instruction: String? = nil,
        modelIdentifier: String? = nil,
        processingRoute: HistoryProcessingRoute? = nil,
        versionID: UUID = UUID(),
        createdAt: Date = .now
    ) throws -> DeliveryEditVersion {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DeliveryEditLineageError.emptyText
        }
        guard origin != .original else { throw DeliveryEditLineageError.invalidOrigin }
        guard !versions.contains(where: { $0.id == versionID }) else {
            throw DeliveryEditLineageError.duplicateVersionID
        }
        guard currentVersion != nil else { throw DeliveryEditLineageError.missingCurrentVersion }

        let version = DeliveryEditVersion(
            id: versionID,
            parentID: currentVersionID,
            createdAt: createdAt,
            text: text,
            origin: origin,
            instruction: instruction,
            modelIdentifier: modelIdentifier,
            processingRoute: processingRoute
        )
        versions.append(version)
        currentVersionID = versionID
        return version
    }

    @discardableResult
    public mutating func undo() -> DeliveryEditVersion? {
        guard let parentID = currentVersion?.parentID,
              let parent = versions.first(where: { $0.id == parentID }) else { return nil }
        currentVersionID = parentID
        return parent
    }

    private enum CodingKeys: String, CodingKey {
        case versions
        case currentVersionID
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let versions = try container.decode([DeliveryEditVersion].self, forKey: .versions)
        let currentVersionID = try container.decode(UUID.self, forKey: .currentVersionID)
        let ids = versions.map(\.id)
        guard !versions.isEmpty,
              Set(ids).count == ids.count,
              ids.contains(currentVersionID) else {
            throw DecodingError.dataCorruptedError(
                forKey: .versions,
                in: container,
                debugDescription: "Delivery edit lineage is invalid."
            )
        }
        self.versions = versions
        self.currentVersionID = currentVersionID
    }
}
