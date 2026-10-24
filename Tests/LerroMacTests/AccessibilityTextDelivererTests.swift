import AppKit
import Foundation
import Testing
import LerroCore
@testable import LerroMac

@Suite("Accessibility text delivery")
struct AccessibilityTextDelivererTests {
    @Test("Strict insertion rejects application drift and secure targets")
    func strictInsertionRejectsDriftAndSecureTarget() async {
        let recorder = DeliveryInvocationRecorder()
        for snapshot in [
            DeliveryFocusSnapshot(safety: .safe, processIdentifier: 99),
            DeliveryFocusSnapshot(safety: .secure, processIdentifier: 42),
        ] {
            let deliverer = AccessibilityTextDeliverer(
                focusSnapshot: { snapshot },
                pasteOverride: { text, _ in await recorder.recordPaste(text) }
            )
            await #expect(throws: LerroError.self) {
                try await deliverer.deliver(
                    "output",
                    to: CapturedContext(
                        applicationName: "Editor",
                        processIdentifier: 42
                    )
                )
            }
        }
        #expect(await recorder.pastedTexts().isEmpty)
    }

    @Test("Strict insertion rejects a missing capture identity")
    func strictInsertionRejectsMissingIdentity() async {
        let missingIdentity = AccessibilityTextDeliverer(
            focusSnapshot: {
                DeliveryFocusSnapshot(safety: .safe, processIdentifier: 42)
            }
        )
        await #expect(throws: LerroError.self) {
            try await missingIdentity.deliver(
                "output",
                to: CapturedContext(applicationName: "Editor")
            )
        }
    }

    @Test("Matching captured target commits one current-focus insert")
    func matchingCurrentInsertCommits() async throws {
        let recorder = DeliveryInvocationRecorder()
        let deliverer = AccessibilityTextDeliverer(
            focusSnapshot: {
                DeliveryFocusSnapshot(
                    safety: .safe,
                    processIdentifier: 42,
                    bundleIdentifier: "com.example.Editor",
                    focusedElementAvailable: false,
                    selectionState: .knownEmpty
                )
            },
            pasteOverride: { text, _ in await recorder.recordPaste(text) }
        )
        try await deliverer.deliver(
            "Lerro delivery probe",
            to: CapturedContext(
                applicationName: "Editor", processIdentifier: 42, bundleIdentifier: "com.example.Editor"
            )
        )
        #expect(await recorder.pastedTexts() == ["Lerro delivery probe"])
    }

    @Test("Concurrent insertions cannot interleave their clipboard transactions")
    func concurrentDeliveriesAreRejected() async throws {
        let blocker = BlockingPasteProbe()
        let deliverer = AccessibilityTextDeliverer(
            focusSnapshot: { DeliveryFocusSnapshot(safety: .safe, processIdentifier: 42, selectionState: .knownEmpty) },
            pasteOverride: { text, _ in await blocker.paste(text) }
        )
        let context = CapturedContext(applicationName: "Editor", processIdentifier: 42)
        let first = Task {
            try await deliverer.deliver("first", to: context)
        }
        await blocker.waitUntilStarted()
        await #expect(throws: LerroError.self) {
            try await deliverer.deliver("second", to: context)
        }
        await blocker.resume()
        _ = try await first.value
        #expect(await blocker.texts() == ["first"])
    }

    @Test("Generated Command-V events carry Lerro source markers")
    func generatedPasteEventsCarrySourceMarkers() throws {
        let events = try makeLerroPasteKeyEvents(keyCode: 9)
        #expect(events.keyDown.flags.intersection(.maskCommand) == .maskCommand)
        #expect(events.keyUp.flags.intersection(.maskCommand) == .maskCommand)
        #expect(events.keyDown.getIntegerValueField(.eventSourceUserData) == LerroGeneratedEvent.pasteSourceUserData)
        #expect(events.keyUp.getIntegerValueField(.eventSourceUserData) == LerroGeneratedEvent.pasteSourceUserData)
    }

    @Test("Pasteboard transaction round-trips ordered multi-item data")
    @MainActor
    func pasteboardTransactionRoundTripsOrderedItems() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        _ = pasteboard.prepareForNewContents(with: [])
        let first = NSPasteboardItem()
        #expect(first.setData(Data("plain".utf8), forType: .string))
        #expect(first.setData(Data([0x01, 0x02]), forType: .init("app.lerro.test.binary")))
        let second = NSPasteboardItem()
        #expect(second.setData(Data("{\\rtf1 test}".utf8), forType: .rtf))
        #expect(pasteboard.writeObjects([first, second]))
        let original = try PasteboardSnapshot.capture(from: pasteboard)
        let transaction = try PasteboardTransaction.begin(
            text: "temporary",
            sessionIdentifier: UUID().uuidString,
            pasteboard: pasteboard
        )
        #expect(try transaction.restoreIfOwned() == .restored)
        #expect(original.matches(pasteboard))
    }

    @Test("Pasteboard transaction preserves a newer external owner")
    @MainActor
    func pasteboardTransactionDoesNotOverwriteExternalUpdate() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        _ = pasteboard.prepareForNewContents(with: [])
        #expect(pasteboard.setString("original", forType: .string))
        let transaction = try PasteboardTransaction.begin(
            text: "temporary",
            sessionIdentifier: UUID().uuidString,
            pasteboard: pasteboard
        )
        _ = pasteboard.prepareForNewContents(with: [])
        #expect(pasteboard.setString("external", forType: .string))
        #expect(try transaction.restoreIfOwned() == .ownershipLost)
        #expect(pasteboard.string(forType: .string) == "external")
    }

    @Test("A temporary pasteboard write failure rolls back")
    @MainActor
    func temporaryPasteboardWriteFailureRollsBack() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        _ = pasteboard.prepareForNewContents(with: [])
        #expect(pasteboard.setString("original", forType: .string))
        let writer = PasteboardWriterProbe(failingCalls: [1])
        #expect(throws: LerroError.self) {
            _ = try PasteboardTransaction.begin(
                text: "temporary",
                sessionIdentifier: UUID().uuidString,
                pasteboard: pasteboard,
                writer: { board, items in
                    writer.write(board, items: items)
                }
            )
        }
        #expect(pasteboard.string(forType: .string) == "original")
        #expect(writer.callCount == 2)
    }

    @Test("Committed Command-V clipboard restore survives caller cancellation")
    @MainActor
    func committedPasteRestoreIsNonCancellable() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        _ = pasteboard.prepareForNewContents(with: [])
        #expect(pasteboard.setString("original", forType: .string))
        let original = try PasteboardSnapshot.capture(from: pasteboard)
        let transaction = try PasteboardTransaction.begin(
            text: "temporary",
            sessionIdentifier: UUID().uuidString,
            pasteboard: pasteboard
        )
        let probe = CommittedDeliveryProbe()
        let caller = Task {
            scheduleCommittedPasteRestore(
                waitForConsumption: { await probe.waitForConsumption() },
                restorePasteboard: {
                    _ = try? await MainActor.run { try transaction.restoreIfOwned() }
                    await probe.recordRestore()
                }
            )
        }
        let restore = await caller.value
        await probe.waitUntilConsumptionStarted()
        caller.cancel()
        await probe.finishConsumption()
        await restore.value
        #expect(await probe.restoreCount() == 1)
        #expect(original.matches(pasteboard))
    }
}

private actor DeliveryInvocationRecorder {
    private var pasted: [String] = []
    func recordPaste(_ text: String) { pasted.append(text) }
    func pastedTexts() -> [String] { pasted }
}

private actor BlockingPasteProbe {
    private var recordedTexts: [String] = []
    private var started = false
    private var continuation: CheckedContinuation<Void, Never>?
    func paste(_ text: String) async {
        recordedTexts.append(text)
        started = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilStarted() async {
        while !started {
            await Task.yield()
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
    func texts() -> [String] { recordedTexts }
}

@MainActor
private final class PasteboardWriterProbe {
    private let failingCalls: Set<Int>
    private(set) var callCount = 0
    init(failingCalls: Set<Int>) { self.failingCalls = failingCalls }
    func write(_ pasteboard: NSPasteboard, items: [NSPasteboardItem]) -> Bool {
        callCount += 1
        return !failingCalls.contains(callCount) && pasteboard.writeObjects(items)
    }
}

private actor CommittedDeliveryProbe {
    private var restores = 0
    private var started = false
    private var continuation: CheckedContinuation<Void, Never>?
    func waitForConsumption() async {
        started = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilConsumptionStarted() async {
        while !started {
            await Task.yield()
        }
    }

    func finishConsumption() {
        continuation?.resume()
        continuation = nil
    }

    func recordRestore() {
        restores += 1
    }
    func restoreCount() -> Int { restores }
}
