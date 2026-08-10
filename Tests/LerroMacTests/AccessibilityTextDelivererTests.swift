import AppKit
import Foundation
import Testing
import LerroCore
@testable import LerroMac

@Suite("Accessibility text delivery")
struct AccessibilityTextDelivererTests {
    @Test("Selection replacement rejects a secure current focus")
    func replacementRejectsSecureFocus() async {
        let deliverer = AccessibilityTextDeliverer(secureFieldCheck: { true })

        do {
            try await deliverer.deliver(
                "sensitive output",
                to: CapturedContext(applicationName: "Tests"),
                replacingSelection: true,
                targetPolicy: .requireCurrent
            )
            Issue.record("Secure-field delivery unexpectedly succeeded")
        } catch LerroError.secureField {
            // Expected privacy boundary.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Selection replacement rejects a context already marked as secure")
    func replacementRejectsSecureContext() async {
        let deliverer = AccessibilityTextDeliverer(secureFieldCheck: { false })

        do {
            try await deliverer.deliver(
                "sensitive output",
                to: CapturedContext(applicationName: "Tests", isSecureField: true),
                replacingSelection: true,
                targetPolicy: .requireCurrent
            )
            Issue.record("Secure context delivery unexpectedly succeeded")
        } catch LerroError.secureField {
            // Expected privacy boundary.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Rejects delivery when the captured application cannot be activated")
    func rejectsFailedActivation() async {
        let deliverer = AccessibilityTextDeliverer(
            activateTarget: { _ in false },
            focusSnapshot: { DeliveryFocusSnapshot(safety: .safe, processIdentifier: 99) }
        )

        await #expect(throws: LerroError.self) {
            try await deliverer.deliver(
                "output",
                to: CapturedContext(applicationName: "Editor", processIdentifier: 42),
                replacingSelection: true,
                targetPolicy: .reactivateCaptured
            )
        }
    }

    @Test("Plain insertion targets the current keyboard focus")
    func plainInsertionUsesCurrentKeyboardFocus() async throws {
        let recorder = DeliveryInvocationRecorder()
        let deliverer = AccessibilityTextDeliverer(
            activateTarget: { _ in true },
            focusSnapshot: { DeliveryFocusSnapshot(safety: .safe, processIdentifier: 99) },
            pasteOverride: { text, _, _ in
                await recorder.recordPaste(text)
            }
        )

        try await deliverer.deliver(
            "output",
            to: CapturedContext(applicationName: "Editor", processIdentifier: 42),
            replacingSelection: false,
            targetPolicy: .requireCurrent
        )

        #expect(await recorder.pastedTexts() == ["output"])
    }

    @Test("Explicit plain insertion reactivates the captured application without AX text")
    func explicitPlainInsertionReactivatesCapturedApplication() async throws {
        let recorder = DeliveryInvocationRecorder()
        let deliverer = AccessibilityTextDeliverer(
            activateTarget: { _ in
                await recorder.recordActivation()
                return true
            },
            focusSnapshot: {
                DeliveryFocusSnapshot(
                    safety: .unavailable,
                    processIdentifier: 42,
                    bundleIdentifier: "com.example.Editor",
                    focusedElementAvailable: false,
                    selectionState: .unavailable
                )
            },
            pasteOverride: { text, _, _ in
                await recorder.recordPaste(text)
            }
        )

        try await deliverer.deliver(
            "answer",
            to: CapturedContext(
                applicationName: "Editor",
                processIdentifier: 42,
                bundleIdentifier: "com.example.Editor"
            ),
            replacingSelection: false,
            targetPolicy: .reactivateCaptured
        )

        #expect(await recorder.activationCount() == 1)
        #expect(await recorder.pastedTexts() == ["answer"])
    }

    @Test("Cancellation after activation stops before any delivery attempt")
    func cancellationAfterActivationStopsDelivery() async {
        let deliverer = AccessibilityTextDeliverer(
            activateTarget: { _ in
                try? await Task.sleep(for: .seconds(5))
                return true
            },
            focusSnapshot: { DeliveryFocusSnapshot(safety: .safe, processIdentifier: 99) }
        )
        let delivery = Task {
            try await deliverer.deliver(
                "output",
                to: CapturedContext(applicationName: "Editor", processIdentifier: 42),
                replacingSelection: true,
                targetPolicy: .reactivateCaptured
            )
        }

        try? await Task.sleep(for: .milliseconds(20))
        delivery.cancel()

        do {
        _ = try await delivery.value
            Issue.record("Cancelled delivery unexpectedly completed")
        } catch is CancellationError {
            // Expected cancellation boundary.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Rejects rewrite after the original selection changes")
    func rejectsChangedSelection() async {
        let deliverer = AccessibilityTextDeliverer(
            activateTarget: { _ in true },
            focusSnapshot: {
                DeliveryFocusSnapshot(
                    safety: .safe,
                    processIdentifier: 42,
                    selectedText: "new selection"
                )
            }
        )

        await #expect(throws: LerroError.self) {
            try await deliverer.deliver(
                "rewritten",
                to: CapturedContext(
                    applicationName: "Editor",
                    processIdentifier: 42,
                    selectedText: "original selection"
                ),
                replacingSelection: true,
                targetPolicy: .requireCurrent
            )
        }
    }

    @Test("Rejects a same-prefix selection whose complete fingerprint changed")
    func rejectsChangedSelectionBeyondPromptLimit() async {
        let prefix = String(repeating: "a", count: 4_096)
        let original = prefix + "original tail"
        let changed = prefix + "modified tail"
        let deliverer = AccessibilityTextDeliverer(
            activateTarget: { _ in true },
            focusSnapshot: {
                DeliveryFocusSnapshot(
                    safety: .safe,
                    processIdentifier: 42,
                    selectedText: prefix,
                    selectedTextFingerprint: changed.hashValue
                )
            }
        )

        await #expect(throws: LerroError.self) {
            try await deliverer.deliver(
                "rewritten",
                to: CapturedContext(
                    applicationName: "Editor",
                    processIdentifier: 42,
                    selectedText: prefix,
                    selectedTextFingerprint: original.hashValue
                ),
                replacingSelection: true,
                targetPolicy: .requireCurrent
            )
        }
    }

    @Test("Plain insertion works when AX has no focused element")
    func plainInsertionWorksWithoutFocusedElement() async throws {
        let recorder = DeliveryInvocationRecorder()
        let deliverer = AccessibilityTextDeliverer(
            activateTarget: { _ in
                await recorder.recordActivation()
                return true
            },
            focusSnapshot: {
                DeliveryFocusSnapshot(
                    safety: .safe,
                    processIdentifier: 42,
                    bundleIdentifier: "com.example.Editor",
                    focusedElementAvailable: false
                )
            },
            pasteOverride: { text, _, _ in
                await recorder.recordPaste(text)
            }
        )

        try await deliverer.deliver(
            "Lerro delivery probe 7F3C2A",
            to: CapturedContext(
                applicationName: "Editor",
                processIdentifier: 42,
                bundleIdentifier: "com.example.Editor"
            ),
            replacingSelection: false,
            targetPolicy: .requireCurrent
        )

        #expect(await recorder.activationCount() == 0)
        #expect(await recorder.pastedTexts() == ["Lerro delivery probe 7F3C2A"])
    }

    @Test("Plain insertion works when AX selection is unavailable")
    func plainInsertionWorksWithoutSelectionState() async throws {
        let recorder = DeliveryInvocationRecorder()
        let deliverer = AccessibilityTextDeliverer(
            activateTarget: { _ in true },
            focusSnapshot: {
                DeliveryFocusSnapshot(
                    safety: .safe,
                    processIdentifier: 42,
                    focusedElementAvailable: true,
                    selectionState: .unavailable
                )
            },
            pasteOverride: { text, _, _ in
                await recorder.recordPaste(text)
            }
        )

        try await deliverer.deliver(
            "delivered",
            to: CapturedContext(applicationName: "Editor", processIdentifier: 42),
            replacingSelection: false,
            targetPolicy: .requireCurrent
        )
        #expect(await recorder.pastedTexts() == ["delivered"])
    }

    @Test("Plain insertion does not depend on the AX safety snapshot")
    func plainInsertionDoesNotRequireAXSafetySnapshot() async throws {
        let recorder = DeliveryInvocationRecorder()
        let deliverer = AccessibilityTextDeliverer(
            activateTarget: { _ in true },
            focusSnapshot: {
                DeliveryFocusSnapshot(
                    safety: .secure,
                    processIdentifier: 42,
                    focusedElementAvailable: false
                )
            },
            pasteOverride: { text, _, _ in
                await recorder.recordPaste(text)
            }
        )

        try await deliverer.deliver(
            "delivered",
            to: CapturedContext(applicationName: "Editor", processIdentifier: 42),
            replacingSelection: false,
            targetPolicy: .requireCurrent
        )
        #expect(await recorder.pastedTexts() == ["delivered"])
    }

    @Test("Plain insertion remains available when capture observed a selection")
    func plainInsertionWithCapturedSelectionUsesCurrentFocus() async throws {
        let recorder = DeliveryInvocationRecorder()
        let deliverer = AccessibilityTextDeliverer(
            activateTarget: { _ in true },
            focusSnapshot: {
                DeliveryFocusSnapshot(
                    safety: .safe,
                    processIdentifier: 42,
                    focusedElementAvailable: false
                )
            },
            pasteOverride: { text, _, _ in
                await recorder.recordPaste(text)
            }
        )

        try await deliverer.deliver(
            "insert at current focus",
            to: CapturedContext(
                applicationName: "Editor",
                processIdentifier: 42,
                selectedText: "selected"
            ),
            replacingSelection: false,
            targetPolicy: .requireCurrent
        )
        #expect(await recorder.pastedTexts() == ["insert at current focus"])
    }

    @Test("Selection replacement requires an inspectable focused element")
    func replacementRequiresFocusedElement() async {
        let recorder = DeliveryInvocationRecorder()
        let deliverer = AccessibilityTextDeliverer(
            activateTarget: { _ in true },
            focusSnapshot: {
                DeliveryFocusSnapshot(
                    safety: .safe,
                    processIdentifier: 42,
                    focusedElementAvailable: false
                )
            },
            pasteOverride: { text, _, _ in
                await recorder.recordPaste(text)
            }
        )

        await #expect(throws: LerroError.self) {
            try await deliverer.deliver(
                "rewritten",
                to: CapturedContext(
                    applicationName: "Editor",
                    processIdentifier: 42,
                    selectedText: "original"
                ),
                replacingSelection: true,
                targetPolicy: .requireCurrent
            )
        }
        #expect(await recorder.pastedTexts().isEmpty)
    }

    @Test("Selection replacement requires an inspectable selection")
    func replacementRequiresSelectionState() async {
        let recorder = DeliveryInvocationRecorder()
        let deliverer = AccessibilityTextDeliverer(
            activateTarget: { _ in true },
            focusSnapshot: {
                DeliveryFocusSnapshot(
                    safety: .safe,
                    processIdentifier: 42,
                    focusedElementAvailable: true,
                    selectionState: .unavailable
                )
            },
            pasteOverride: { text, _, _ in
                await recorder.recordPaste(text)
            }
        )

        await #expect(throws: LerroError.self) {
            try await deliverer.deliver(
                "rewritten",
                to: CapturedContext(
                    applicationName: "Editor",
                    processIdentifier: 42,
                    selectedText: "original"
                ),
                replacingSelection: true,
                targetPolicy: .requireCurrent
            )
        }
        #expect(await recorder.pastedTexts().isEmpty)
    }

    @Test("Selection replacement delivers when the original selection still matches")
    func matchingReplacementDelivers() async throws {
        let recorder = DeliveryInvocationRecorder()
        let original = "original"
        let deliverer = AccessibilityTextDeliverer(
            activateTarget: { _ in true },
            focusSnapshot: {
                DeliveryFocusSnapshot(
                    safety: .safe,
                    processIdentifier: 42,
                    selectedText: original,
                    selectedTextFingerprint: original.hashValue
                )
            },
            pasteOverride: { text, _, _ in
                await recorder.recordPaste(text)
            }
        )

        try await deliverer.deliver(
            "rewritten",
            to: CapturedContext(
                applicationName: "Editor",
                processIdentifier: 42,
                selectedText: original,
                selectedTextFingerprint: original.hashValue
            ),
            replacingSelection: true,
            targetPolicy: .requireCurrent
        )

        #expect(await recorder.pastedTexts() == ["rewritten"])
    }

    @Test("Selection replacement reactivates the captured app and waits for focus")
    func replacementReactivationWaitsForCapturedTarget() async throws {
        let recorder = DeliveryInvocationRecorder()
        let snapshots = SnapshotSequence([
            DeliveryFocusSnapshot(safety: .safe, processIdentifier: 99),
            DeliveryFocusSnapshot(
                safety: .safe,
                processIdentifier: 42,
                selectedText: "original"
            )
        ])
        let deliverer = AccessibilityTextDeliverer(
            activateTarget: { _ in
                await recorder.recordActivation()
                return true
            },
            focusSnapshot: { snapshots.next() },
            activationPollAttempts: 2,
            pasteOverride: { text, _, _ in
                await recorder.recordPaste(text)
            }
        )

        try await deliverer.deliver(
            "answer",
            to: CapturedContext(
                applicationName: "Editor",
                processIdentifier: 42,
                selectedText: "original"
            ),
            replacingSelection: true,
            targetPolicy: .reactivateCaptured
        )

        #expect(await recorder.activationCount() == 1)
        #expect(await recorder.pastedTexts() == ["answer"])
    }

    @Test("Concurrent deliveries cannot interleave their clipboard transactions")
    func concurrentDeliveriesAreRejected() async throws {
        let blocker = BlockingPasteProbe()
        let deliverer = AccessibilityTextDeliverer(
            activateTarget: { _ in true },
            focusSnapshot: {
                DeliveryFocusSnapshot(
                    safety: .safe,
                    processIdentifier: 42,
                    selectionState: .knownEmpty
                )
            },
            pasteOverride: { text, _, _ in
                await blocker.paste(text)
            }
        )
        let context = CapturedContext(applicationName: "Editor", processIdentifier: 42)
        let first = Task {
            try await deliverer.deliver(
                "first",
                to: context,
                replacingSelection: false,
                targetPolicy: .requireCurrent
            )
        }
        await blocker.waitUntilStarted()

        await #expect(throws: LerroError.self) {
            try await deliverer.deliver(
                "second",
                to: context,
                replacingSelection: false,
                targetPolicy: .requireCurrent
            )
        }

        await blocker.resume()
        _ = try await first.value
        #expect(await blocker.texts() == ["first"])
    }

    @Test("Plain insertion does not require a captured app identity")
    func plainInsertionWorksWithoutTargetIdentity() async throws {
        let recorder = DeliveryInvocationRecorder()
        let deliverer = AccessibilityTextDeliverer(
            activateTarget: { _ in true },
            focusSnapshot: {
                DeliveryFocusSnapshot(safety: .safe, processIdentifier: 42)
            },
            pasteOverride: { text, _, _ in
                await recorder.recordPaste(text)
            }
        )

        try await deliverer.deliver(
            "output",
            to: CapturedContext(applicationName: "Editor"),
            replacingSelection: false,
            targetPolicy: .requireCurrent
        )
        #expect(await recorder.pastedTexts() == ["output"])
    }

    @Test("Selection observations distinguish empty, selected, and unavailable states")
    func resolvesSelectionObservationStates() {
        #expect(
            resolvedTextSelectionState(
                selectedText: "",
                selectedRange: CFRange(location: 3, length: 0)
            ) == .knownEmpty
        )
        #expect(
            resolvedTextSelectionState(
                selectedText: nil,
                selectedRange: CFRange(location: 3, length: 2)
            ) == .knownSelection
        )
        #expect(
            resolvedTextSelectionState(selectedText: "selected", selectedRange: nil)
                == .knownSelection
        )
        #expect(
            resolvedTextSelectionState(selectedText: nil, selectedRange: nil)
                == .unavailable
        )
    }

    @Test("AX text decoding accepts plain and attributed strings")
    func decodesAXTextRepresentations() {
        let plain = "plain" as CFString
        let attributed = NSAttributedString(string: "attributed")

        #expect(decodedAXTextValue(plain) == "plain")
        #expect(decodedAXTextValue(attributed) == "attributed")
        #expect(decodedAXTextValue(NSNumber(value: 7)) == nil)
    }

    @Test("Cursor neighborhood keeps only the tested 80/40 context window")
    func resolvesCursorNeighborhood() {
        let before = String(repeating: "前", count: 90) + "🙂"
        let selected = "选中"
        let after = String(repeating: "后", count: 50)
        let value = before + selected + after
        let selection = CFRange(
            location: (before as NSString).length,
            length: (selected as NSString).length
        )

        let result = resolvedCursorNeighborhood(text: value, selectedRange: selection)

        #expect(result.before.map { ($0 as NSString).length } == 80)
        #expect(result.before?.hasSuffix("🙂") == true)
        #expect(result.after.map { ($0 as NSString).length } == 40)
        #expect(result.after == String(repeating: "后", count: 40))
    }

    @Test("Cursor neighborhood stays unavailable when AX has no caret range")
    func cursorNeighborhoodRequiresRange() {
        let result = resolvedCursorNeighborhood(text: "example", selectedRange: nil)

        #expect(result.before == nil)
        #expect(result.after == nil)
    }

    @Test("Generated paste key events carry Lerro source markers")
    func generatedPasteEventsCarrySourceMarkers() throws {
        let events = try makeLerroPasteKeyEvents(keyCode: 9)

        #expect(events.keyDown.flags.intersection(.maskCommand) == .maskCommand)
        #expect(events.keyUp.flags.intersection(.maskCommand) == .maskCommand)
        #expect(
            events.keyDown.getIntegerValueField(.eventSourceUserData)
                == LerroGeneratedEvent.pasteSourceUserData
        )
        #expect(
            events.keyUp.getIntegerValueField(.eventSourceUserData)
                == LerroGeneratedEvent.pasteSourceUserData
        )
        #expect(events.keyDown.getIntegerValueField(.keyboardEventKeycode) == 9)
        #expect(events.keyUp.getIntegerValueField(.keyboardEventKeycode) == 9)
    }

    @Test("Current-focus paste writes text and a transient marker")
    @MainActor
    func currentFocusPasteUsesTransientTextItem() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        _ = pasteboard.prepareForNewContents(with: [])
        #expect(pasteboard.setString("original", forType: .string))

        let transaction = try CurrentFocusPasteboardTransaction.begin(
            text: "temporary",
            pasteboard: pasteboard
        )

        #expect(pasteboard.string(forType: .string) == "temporary")
        #expect(pasteboard.data(forType: PasteboardSnapshot.transientType) == Data())
        #expect(pasteboard.data(forType: PasteboardSnapshot.sessionType) == nil)
        try transaction.restore()
        #expect(pasteboard.string(forType: .string) == "original")
    }

    @Test("Current-focus paste restores its archive after a newer clipboard write")
    @MainActor
    func currentFocusPasteRestoresArchiveUnconditionally() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        _ = pasteboard.prepareForNewContents(with: [])
        #expect(pasteboard.setString("original", forType: .string))
        let transaction = try CurrentFocusPasteboardTransaction.begin(
            text: "temporary",
            pasteboard: pasteboard
        )
        _ = pasteboard.prepareForNewContents(with: [])
        #expect(pasteboard.setString("newer", forType: .string))

        try transaction.restore()

        #expect(pasteboard.string(forType: .string) == "original")
    }

    @Test("Current-focus paste tolerates an unreadable advertised type")
    @MainActor
    func currentFocusPasteUsesBestEffortArchive() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        _ = pasteboard.prepareForNewContents(with: [])
        let type = NSPasteboard.PasteboardType("app.lerro.test.unreadable-current-focus")
        let item = NSPasteboardItem()
        let provider = EmptyPasteboardDataProvider()
        item.setDataProvider(provider, forTypes: [type])
        #expect(pasteboard.writeObjects([item]))

        let transaction = try CurrentFocusPasteboardTransaction.begin(
            text: "temporary",
            pasteboard: pasteboard
        )

        #expect(pasteboard.string(forType: .string) == "temporary")
        try? transaction.restore()
    }

    @Test("Pasteboard transaction restores ordered multi-item data exactly")
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
        #expect(second.setData(Data([0x03, 0x04]), forType: .init("app.lerro.test.custom")))
        #expect(pasteboard.writeObjects([first, second]))

        let original = try PasteboardSnapshot.capture(from: pasteboard)
        let transaction = try PasteboardTransaction.begin(
            text: "temporary",
            sessionIdentifier: UUID().uuidString,
            pasteboard: pasteboard
        )
        #expect(transaction.isOwned())
        #expect(try transaction.restoreIfOwned() == .restored)
        #expect(original.matches(pasteboard))
    }

    @Test("Pasteboard transaction preserves a newer external clipboard owner")
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
        let externalChangeCount = pasteboard.changeCount

        #expect(try transaction.restoreIfOwned() == .ownershipLost)
        #expect(pasteboard.changeCount == externalChangeCount)
        #expect(pasteboard.string(forType: .string) == "external")
    }

    @Test("Pasteboard transaction restores an originally empty clipboard")
    @MainActor
    func pasteboardTransactionRestoresEmptyClipboard() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        _ = pasteboard.prepareForNewContents(with: [])

        let transaction = try PasteboardTransaction.begin(
            text: "temporary",
            sessionIdentifier: UUID().uuidString,
            pasteboard: pasteboard
        )

        #expect(try transaction.restoreIfOwned() == .restored)
        #expect(pasteboard.pasteboardItems?.isEmpty == true)
    }

    @Test("Unreadable advertised pasteboard data fails before mutation")
    @MainActor
    func unreadablePasteboardDataFailsClosed() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        _ = pasteboard.prepareForNewContents(with: [])
        let type = NSPasteboard.PasteboardType("app.lerro.test.unreadable")
        let item = NSPasteboardItem()
        let provider = EmptyPasteboardDataProvider()
        item.setDataProvider(provider, forTypes: [type])
        #expect(pasteboard.writeObjects([item]))
        let changeCount = pasteboard.changeCount

        #expect(throws: LerroError.self) {
            _ = try PasteboardTransaction.begin(
                text: "temporary",
                sessionIdentifier: UUID().uuidString,
                pasteboard: pasteboard
            )
        }
        #expect(pasteboard.changeCount == changeCount)
    }

    @Test("Temporary pasteboard write failure rolls the original content back")
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
                writer: { board, items in writer.write(board, items: items) }
            )
        }

        #expect(pasteboard.string(forType: .string) == "original")
        #expect(writer.callCount == 2)
    }

    @Test("Pasteboard restore retries with fresh item instances")
    @MainActor
    func pasteboardRestoreRetriesWithFreshItems() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        _ = pasteboard.prepareForNewContents(with: [])
        #expect(pasteboard.setString("original", forType: .string))
        let transaction = try PasteboardTransaction.begin(
            text: "temporary",
            sessionIdentifier: UUID().uuidString,
            pasteboard: pasteboard
        )
        let writer = PasteboardWriterProbe(failingCalls: [1])

        #expect(
            try transaction.restoreIfOwned(
                writer: { board, items in writer.write(board, items: items) }
            ) == .restored
        )
        #expect(writer.callCount == 2)
        #expect(writer.itemIdentities.count == 2)
        #expect(writer.itemIdentities[0] != writer.itemIdentities[1])
        #expect(pasteboard.string(forType: .string) == "original")
    }

    @Test("Repeated pasteboard restore failure is surfaced")
    @MainActor
    func repeatedPasteboardRestoreFailureThrows() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        _ = pasteboard.prepareForNewContents(with: [])
        #expect(pasteboard.setString("original", forType: .string))
        let transaction = try PasteboardTransaction.begin(
            text: "temporary",
            sessionIdentifier: UUID().uuidString,
            pasteboard: pasteboard
        )
        let writer = PasteboardWriterProbe(failingCalls: [1, 2])

        #expect(throws: LerroError.self) {
            _ = try transaction.restoreIfOwned(
                writer: { board, items in writer.write(board, items: items) }
            )
        }
        #expect(writer.callCount == 2)
    }

    @Test("Committed paste finalization survives caller cancellation and restores once")
    @MainActor
    func committedPasteFinalizationIsNonCancellable() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        _ = pasteboard.prepareForNewContents(with: [])
        let first = NSPasteboardItem()
        #expect(first.setData(Data("original".utf8), forType: .string))
        #expect(first.setData(Data([0x01, 0x02]), forType: .init("app.lerro.test.binary")))
        let second = NSPasteboardItem()
        #expect(second.setData(Data("{\\rtf1 original}".utf8), forType: .rtf))
        #expect(pasteboard.writeObjects([first, second]))
        let original = try PasteboardSnapshot.capture(from: pasteboard)
        let transaction = try PasteboardTransaction.begin(
            text: "temporary",
            sessionIdentifier: UUID().uuidString,
            pasteboard: pasteboard
        )
        let probe = CommittedDeliveryProbe()
        let finalization = Task {
            try await finalizeCommittedPasteDelivery(
                waitForConsumption: {
                    await probe.waitForConsumption()
                },
                restorePasteboard: {
                    _ = try await MainActor.run {
                        try transaction.restoreIfOwned()
                    }
                    await probe.recordRestore()
                }
            )
        }

        await probe.waitUntilConsumptionStarted()
        finalization.cancel()
        await probe.finishConsumption()
        try await finalization.value

        #expect(await probe.waitCount() == 1)
        #expect(await probe.restoreCount() == 1)
        #expect(original.matches(pasteboard))
    }

    @Test("Receipt validation requires the same target and exact focused value")
    func validatesReceiptTargetAndValue() throws {
        let context = CapturedContext(
            applicationName: "Notes",
            processIdentifier: 42,
            bundleIdentifier: "com.apple.Notes",
            role: "AXTextArea"
        )
        let receipt = TextDeliveryReceipt(
            context: context,
            focusedValueFingerprint: 99,
            focusedElementFingerprint: 7
        )
        let valid = DeliveryFocusSnapshot(
            safety: .safe,
            processIdentifier: 42,
            bundleIdentifier: "com.apple.Notes",
            focusedValueFingerprint: 99,
            focusedElementFingerprint: 7,
            role: "AXTextArea"
        )

        #expect(receiptFocusMatches(valid, receipt: receipt))
        try validateReceiptFocus(valid, receipt: receipt)

        var edited = valid
        edited.focusedValueFingerprint = 100
        do {
            try validateReceiptFocus(edited, receipt: receipt)
            Issue.record("Edited text unexpectedly kept the receipt valid")
        } catch let error as LerroError {
            #expect(error.localizedDescription.contains("输入内容已经变化"))
        }

        var switched = valid
        switched.bundleIdentifier = "com.apple.TextEdit"
        do {
            try validateReceiptFocus(switched, receipt: receipt)
            Issue.record("Switched application unexpectedly kept the receipt valid")
        } catch let error as LerroError {
            #expect(error.localizedDescription.contains("焦点已切换"))
        }
    }

    @Test("Corrections can chain and restore earlier text through fresh receipts")
    func correctionsChainThroughFreshReceipts() async throws {
        let context = CapturedContext(
            applicationName: "Notes",
            processIdentifier: 42,
            bundleIdentifier: "com.apple.Notes",
            role: "AXTextArea"
        )
        let original = receiptSnapshot(value: 11)
        let shortened = receiptSnapshot(value: 22)
        let renamed = receiptSnapshot(value: 33)
        let snapshots = SnapshotSequence([
            original, original, shortened,
            shortened, shortened, renamed,
            renamed, renamed, original,
        ])
        let actions = ReceiptActionRecorder()
        let deliverer = AccessibilityTextDeliverer(
            activateTarget: { _ in true },
            focusSnapshot: { snapshots.next() },
            receiptActionOverride: { action, receipt in
                await actions.record(action, receipt: receipt)
            }
        )
        let firstReceipt = TextDeliveryReceipt(
            context: context,
            focusedValueFingerprint: 11,
            focusedElementFingerprint: 7
        )

        let shortenedReceipt = try await deliverer.correct(
            "shortened",
            using: firstReceipt
        )
        let renamedReceipt = try await deliverer.correct(
            "renamed",
            using: shortenedReceipt
        )
        let restoredReceipt = try await deliverer.correct(
            "original",
            using: renamedReceipt
        )

        #expect(shortenedReceipt.id != firstReceipt.id)
        #expect(renamedReceipt.id != shortenedReceipt.id)
        #expect(restoredReceipt.id != renamedReceipt.id)
        #expect(shortenedReceipt.focusedValueFingerprint == 22)
        #expect(renamedReceipt.focusedValueFingerprint == 33)
        #expect(restoredReceipt.focusedValueFingerprint == 11)
        #expect(shortenedReceipt.canUndo)
        #expect(renamedReceipt.canUndo)
        #expect(restoredReceipt.canUndo)
        #expect(
            await actions.actions() == [
                .correct("shortened"),
                .correct("renamed"),
                .correct("original"),
            ]
        )
        #expect(
            await actions.receiptIDs() == [
                firstReceipt.id,
                shortenedReceipt.id,
                renamedReceipt.id,
            ]
        )
    }

    @Test("Correction rejects app, security, value, and element drift before acting")
    func correctionRejectsReceiptDrift() async {
        let context = CapturedContext(
            applicationName: "Notes",
            processIdentifier: 42,
            bundleIdentifier: "com.apple.Notes",
            role: "AXTextArea"
        )
        let receipt = TextDeliveryReceipt(
            context: context,
            focusedValueFingerprint: 11,
            focusedElementFingerprint: 7
        )
        let driftedSnapshots = [
            DeliveryFocusSnapshot(
                safety: .safe,
                processIdentifier: 99,
                bundleIdentifier: "com.apple.TextEdit",
                focusedValueFingerprint: 11,
                focusedElementFingerprint: 7
            ),
            DeliveryFocusSnapshot(
                safety: .secure,
                processIdentifier: 42,
                bundleIdentifier: "com.apple.Notes",
                focusedValueFingerprint: 11,
                focusedElementFingerprint: 7
            ),
            receiptSnapshot(value: 12),
            receiptSnapshot(value: 11, element: 8),
        ]

        for snapshot in driftedSnapshots {
            let actions = ReceiptActionRecorder()
            let deliverer = AccessibilityTextDeliverer(
                activateTarget: { _ in false },
                focusSnapshot: { snapshot },
                receiptActionOverride: { action, receipt in
                    await actions.record(action, receipt: receipt)
                }
            )

            await #expect(throws: LerroError.self) {
                try await deliverer.correct("changed", using: receipt)
            }
            #expect(await actions.actions().isEmpty)
        }
    }

    @Test("Correction requires a fully bound receipt")
    func correctionRequiresBoundReceipt() async {
        let actions = ReceiptActionRecorder()
        let snapshot = receiptSnapshot(value: 11)
        let deliverer = AccessibilityTextDeliverer(
            activateTarget: { _ in true },
            focusSnapshot: { snapshot },
            receiptActionOverride: { action, receipt in
                await actions.record(action, receipt: receipt)
            }
        )
        let receipt = TextDeliveryReceipt(
            context: CapturedContext(
                applicationName: "Notes",
                processIdentifier: 42,
                bundleIdentifier: "com.apple.Notes"
            ),
            focusedValueFingerprint: 11
        )

        await #expect(throws: LerroError.self) {
            try await deliverer.correct("changed", using: receipt)
        }
        #expect(await actions.actions().isEmpty)
    }

    @Test("A focus switch after correction disables the returned receipt")
    func correctionPostCommitFocusSwitchInvalidatesReceipt() async throws {
        let context = CapturedContext(
            applicationName: "Notes",
            processIdentifier: 42,
            bundleIdentifier: "com.apple.Notes",
            role: "AXTextArea"
        )
        let original = receiptSnapshot(value: 11)
        let switched = DeliveryFocusSnapshot(
            safety: .safe,
            processIdentifier: 99,
            bundleIdentifier: "com.apple.TextEdit",
            focusedValueFingerprint: 22,
            focusedElementFingerprint: 8
        )
        let snapshots = SnapshotSequence([original, original, switched])
        let actions = ReceiptActionRecorder()
        let deliverer = AccessibilityTextDeliverer(
            activateTarget: { _ in true },
            focusSnapshot: { snapshots.next() },
            receiptActionOverride: { action, receipt in
                await actions.record(action, receipt: receipt)
            }
        )
        let receipt = TextDeliveryReceipt(
            context: context,
            focusedValueFingerprint: 11,
            focusedElementFingerprint: 7
        )

        let nextReceipt = try await deliverer.correct("changed", using: receipt)

        #expect(nextReceipt.context.processIdentifier == 42)
        #expect(nextReceipt.context.bundleIdentifier == "com.apple.Notes")
        #expect(nextReceipt.focusedValueFingerprint == nil)
        #expect(nextReceipt.focusedElementFingerprint == nil)
        #expect(!nextReceipt.canUndo)
        #expect(await actions.actions() == [.correct("changed")])
    }

    @Test("Concurrent corrections cannot interleave their receipt transactions")
    func concurrentCorrectionsAreRejected() async throws {
        let context = CapturedContext(
            applicationName: "Notes",
            processIdentifier: 42,
            bundleIdentifier: "com.apple.Notes",
            role: "AXTextArea"
        )
        let snapshot = receiptSnapshot(value: 11)
        let blocker = BlockingReceiptActionRecorder()
        let deliverer = AccessibilityTextDeliverer(
            activateTarget: { _ in true },
            focusSnapshot: { snapshot },
            receiptActionOverride: { action, _ in
                await blocker.recordAndWait(action)
            }
        )
        let receipt = TextDeliveryReceipt(
            context: context,
            focusedValueFingerprint: 11,
            focusedElementFingerprint: 7
        )
        let first = Task {
            try await deliverer.correct("first", using: receipt)
        }
        await blocker.waitUntilStarted()

        await #expect(throws: LerroError.self) {
            try await deliverer.correct("second", using: receipt)
        }

        await blocker.resume()
        _ = try await first.value
        #expect(await blocker.actions() == [.correct("first")])
    }

    private func receiptSnapshot(
        value: Int,
        element: Int = 7
    ) -> DeliveryFocusSnapshot {
        DeliveryFocusSnapshot(
            safety: .safe,
            processIdentifier: 42,
            bundleIdentifier: "com.apple.Notes",
            applicationName: "Notes",
            focusedValueFingerprint: value,
            focusedElementFingerprint: element,
            role: "AXTextArea"
        )
    }
}

@MainActor
private final class EmptyPasteboardDataProvider: NSObject, NSPasteboardItemDataProvider {
    func pasteboard(
        _ pasteboard: NSPasteboard?,
        item: NSPasteboardItem,
        provideDataForType type: NSPasteboard.PasteboardType
    ) {}
}

@MainActor
private final class PasteboardWriterProbe {
    private let failingCalls: Set<Int>
    private(set) var callCount = 0
    private(set) var itemIdentities: [[ObjectIdentifier]] = []

    init(failingCalls: Set<Int>) {
        self.failingCalls = failingCalls
    }

    func write(_ pasteboard: NSPasteboard, items: [NSPasteboardItem]) -> Bool {
        callCount += 1
        itemIdentities.append(items.map(ObjectIdentifier.init))
        guard !failingCalls.contains(callCount) else { return false }
        return pasteboard.writeObjects(items)
    }
}

private actor DeliveryInvocationRecorder {
    private var activations = 0
    private var pasted: [String] = []

    func recordActivation() {
        activations += 1
    }

    func recordPaste(_ text: String) {
        pasted.append(text)
    }

    func activationCount() -> Int { activations }
    func pastedTexts() -> [String] { pasted }
}

private actor ReceiptActionRecorder {
    private var recordedActions: [ReceiptAction] = []
    private var recordedReceiptIDs: [UUID] = []

    func record(_ action: ReceiptAction, receipt: TextDeliveryReceipt) {
        recordedActions.append(action)
        recordedReceiptIDs.append(receipt.id)
    }

    func actions() -> [ReceiptAction] { recordedActions }
    func receiptIDs() -> [UUID] { recordedReceiptIDs }
}

private actor BlockingReceiptActionRecorder {
    private var recordedActions: [ReceiptAction] = []
    private var started = false
    private var continuation: CheckedContinuation<Void, Never>?

    func recordAndWait(_ action: ReceiptAction) async {
        recordedActions.append(action)
        started = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilStarted() async {
        while !started { await Task.yield() }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }

    func actions() -> [ReceiptAction] { recordedActions }
}

private final class SnapshotSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [DeliveryFocusSnapshot]
    private var index = 0

    init(_ snapshots: [DeliveryFocusSnapshot]) {
        self.snapshots = snapshots
    }

    func next() -> DeliveryFocusSnapshot {
        lock.lock()
        defer { lock.unlock() }
        guard !snapshots.isEmpty else {
            return DeliveryFocusSnapshot(safety: .unavailable)
        }
        let snapshot = snapshots[min(index, snapshots.count - 1)]
        index += 1
        return snapshot
    }
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

private actor CommittedDeliveryProbe {
    private var waits = 0
    private var restores = 0
    private var consumptionStarted = false
    private var continuation: CheckedContinuation<Void, Never>?

    func waitForConsumption() async {
        waits += 1
        consumptionStarted = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilConsumptionStarted() async {
        while !consumptionStarted {
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

    func waitCount() -> Int { waits }
    func restoreCount() -> Int { restores }
}
