import AppKit
import Foundation
import LerroCore
import Testing
@testable import LerroMac

@Suite("V1.6 macOS adapters")
struct V16SystemAdapterTests {
    @Test("Automatic learning emits the smallest edit inside the uniquely inserted text")
    func observedEditIsScopedToDeliveredText() throws {
        let edit = try #require(
            minimalObservedDeliveredTextEdit(
                original: "prefix 乐若 很好 suffix",
                corrected: "prefix Lerro 很好 suffix",
                deliveredText: "乐若 很好",
                applicationName: "ChatGPT",
                bundleIdentifier: "com.openai.chat"
            )
        )

        #expect(edit.originalSpan == "乐若")
        #expect(edit.correctedSpan == "Lerro")
        #expect(edit.contextBefore == "prefix ")
        #expect(edit.contextAfter == " 很好 suffix")
    }

    @Test("Edits elsewhere in the same field are ignored")
    func unrelatedFieldEditIsIgnored() {
        let edit = minimalObservedDeliveredTextEdit(
            original: "old prefix 乐若 很好 suffix",
            corrected: "new prefix 乐若 很好 suffix",
            deliveredText: "乐若 很好",
            applicationName: "ChatGPT",
            bundleIdentifier: "com.openai.chat"
        )

        #expect(edit == nil)
    }

    @Test("Duplicate delivered text is not observed because its position is ambiguous")
    func duplicateOccurrenceIsIgnored() {
        let edit = minimalObservedDeliveredTextEdit(
            original: "乐若 很好 / 乐若 很好",
            corrected: "Lerro 很好 / 乐若 很好",
            deliveredText: "乐若 很好",
            applicationName: "ChatGPT",
            bundleIdentifier: nil
        )

        #expect(edit == nil)
    }

    @Test("Recovery copying deliberately keeps exact text on the pasteboard")
    @MainActor
    func recoveryClipboardKeepsExactText() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        try await PasteboardRecoveryTextCopier(
            pasteboardName: pasteboard.name.rawValue
        ).copyForRecovery("Lerro recovery 🙂")

        #expect(pasteboard.string(forType: .string) == "Lerro recovery 🙂")
    }

    @Test("Application catalog merges duplicate bundles and places running apps first")
    func applicationCatalogMergesInstalledAndRunning() {
        let merged = mergedApplicationDescriptors(
            installed: [
                ApplicationDescriptor(
                    bundleIdentifier: "com.example.Editor",
                    name: "Editor",
                    bundleURL: "/Applications/Editor.app"
                ),
                ApplicationDescriptor(bundleIdentifier: "com.example.Notes", name: "Notes"),
            ],
            running: [
                ApplicationDescriptor(
                    bundleIdentifier: "com.example.Editor",
                    name: "Editor Running",
                    isRunning: true
                ),
            ]
        )

        #expect(merged.count == 2)
        #expect(merged.first?.bundleIdentifier == "com.example.Editor")
        #expect(merged.first?.name == "Editor Running")
        #expect(merged.first?.bundleURL == "/Applications/Editor.app")
        #expect(merged.first?.isRunning == true)
    }

    @Test("Strict delivery rejects application, element, value, range, and secure drift")
    func strictDeliveryValidation() {
        let context = CapturedContext(
            applicationName: "Editor",
            processIdentifier: 42,
            bundleIdentifier: "com.example.Editor",
            selectionState: .knownEmpty,
            focusedElementAvailable: true,
            focusedElementFingerprint: 10,
            focusedValueFingerprint: 20,
            selectedRange: UTF16TextRange(location: 3, length: 0)
        )
        let matching = DeliveryFocusSnapshot(
            safety: .safe,
            processIdentifier: 42,
            bundleIdentifier: "com.example.Editor",
            selectionState: .knownEmpty,
            focusedValueFingerprint: 20,
            focusedElementFingerprint: 10,
            selectedRange: UTF16TextRange(location: 3, length: 0)
        )

        #expect(throws: Never.self) {
            try validateExpectedFocusForTesting(matching, context: context)
        }
        var appDrift = matching
        appDrift.processIdentifier = 99
        #expect(throws: LerroError.self) {
            try validateExpectedFocusForTesting(appDrift, context: context)
        }
        var elementDrift = matching
        elementDrift.focusedElementFingerprint = 11
        #expect(throws: LerroError.self) {
            try validateExpectedFocusForTesting(elementDrift, context: context)
        }
        var valueDrift = matching
        valueDrift.focusedValueFingerprint = 21
        #expect(throws: LerroError.self) {
            try validateExpectedFocusForTesting(valueDrift, context: context)
        }
        var rangeDrift = matching
        rangeDrift.selectedRange = UTF16TextRange(location: 4, length: 0)
        #expect(throws: LerroError.self) {
            try validateExpectedFocusForTesting(rangeDrift, context: context)
        }
        var secureDrift = matching
        secureDrift.safety = .secure
        #expect(throws: LerroError.self) {
            try validateExpectedFocusForTesting(secureDrift, context: context)
        }
    }
}
