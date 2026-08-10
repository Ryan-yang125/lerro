import Foundation
import Testing
@testable import LerroCore

@Suite("Delivery edit lineage")
struct DeliveryEditLineageTests {
    @Test("Tracks stacked edits, undo, and a branch after undo")
    func tracksVersionBranches() throws {
        let originalID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let shortID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let replaceID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        let branchID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000004"))
        var lineage = try DeliveryEditLineage(
            originalText: "Original text",
            versionID: originalID,
            createdAt: Date(timeIntervalSince1970: 1)
        )

        try lineage.append(
            text: "Short text",
            origin: .semantic,
            instruction: "改短一点",
            versionID: shortID,
            createdAt: Date(timeIntervalSince1970: 2)
        )
        try lineage.append(
            text: "Short Toni text",
            origin: .deterministic,
            instruction: "把名字改成 Toni",
            versionID: replaceID,
            createdAt: Date(timeIntervalSince1970: 3)
        )

        #expect(lineage.currentVersion?.text == "Short Toni text")
        #expect(lineage.currentPath.map(\.id) == [originalID, shortID, replaceID])
        #expect(lineage.undo()?.id == shortID)
        #expect(lineage.undo()?.id == originalID)
        #expect(!lineage.canUndo)

        try lineage.append(
            text: "Redictated text",
            origin: .redictation,
            instruction: "重新听写",
            versionID: branchID,
            createdAt: Date(timeIntervalSince1970: 4)
        )
        #expect(lineage.versions.map(\.id) == [originalID, shortID, replaceID, branchID])
        #expect(lineage.currentPath.map(\.id) == [originalID, branchID])
    }

    @Test("Round-trips through history persistence")
    func roundTripsWithHistory() throws {
        var lineage = try DeliveryEditLineage(originalText: "Original")
        try lineage.append(
            text: "Edited",
            origin: .semantic,
            instruction: "Make it warmer"
        )
        let history = HistoryEntry(
            mode: .dictation,
            rawText: "Original",
            finalText: "Edited",
            duration: 1,
            applicationName: "Notes",
            editLineage: lineage
        )

        let encoded = try JSONEncoder().encode(history)
        let decoded = try JSONDecoder().decode(HistoryEntry.self, from: encoded)
        #expect(decoded == history)
        #expect(decoded.editLineage?.currentVersion?.text == "Edited")
    }

    @Test("Rejects invalid mutations and corrupt persisted state")
    func rejectsInvalidState() throws {
        #expect(throws: DeliveryEditLineageError.emptyText) {
            try DeliveryEditLineage(originalText: "  ")
        }

        let originalID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        var lineage = try DeliveryEditLineage(originalText: "Original", versionID: originalID)
        #expect(throws: DeliveryEditLineageError.invalidOrigin) {
            try lineage.append(text: "Duplicate root", origin: .original)
        }
        #expect(throws: DeliveryEditLineageError.duplicateVersionID) {
            try lineage.append(text: "Duplicate ID", origin: .semantic, versionID: originalID)
        }

        let corrupt = Data(#"{"versions":[],"currentVersionID":"00000000-0000-0000-0000-000000000001"}"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(DeliveryEditLineage.self, from: corrupt)
        }
    }
}
