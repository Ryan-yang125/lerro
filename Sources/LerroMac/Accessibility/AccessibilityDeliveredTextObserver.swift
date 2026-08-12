import AppKit
import ApplicationServices
import Carbon
import Foundation
import LerroCore

public actor AccessibilityDeliveredTextObserver: DeliveredTextObserving {
    static let debounceDuration: Duration = .milliseconds(800)
    static let pollInterval: Duration = .milliseconds(100)
    static let maximumObservedUTF16Length = 65_536

    private var observationTask: Task<Void, Never>?
    private var continuation: AsyncThrowingStream<DeliveredTextEdit, any Error>.Continuation?
    private var observationGeneration: UUID?

    public init() {}

    public func observe(
        text: String,
        receipt: TextDeliveryReceipt,
        timeout: Duration
    ) async throws -> AsyncThrowingStream<DeliveredTextEdit, any Error> {
        await stopObserving()
        let baseline = try await observedTargetValue(receipt: receipt)
        guard baseline.contains(text) else {
            throw LerroError.insertionFailed("当前编辑器无法绑定刚写入的文本")
        }
        let pair = AsyncThrowingStream<DeliveredTextEdit, any Error>.makeStream()
        continuation = pair.continuation
        let generation = UUID()
        observationGeneration = generation
        observationTask = Task { [weak self] in
            await self?.runObservation(
                generation: generation,
                baseline: baseline,
                deliveredText: text,
                receipt: receipt,
                timeout: timeout,
                continuation: pair.continuation
            )
        }
        return pair.stream
    }

    public func stopObserving() async {
        observationTask?.cancel()
        observationTask = nil
        continuation?.finish()
        continuation = nil
        observationGeneration = nil
    }

    private func runObservation(
        generation: UUID,
        baseline initialBaseline: String,
        deliveredText: String,
        receipt: TextDeliveryReceipt,
        timeout: Duration,
        continuation: AsyncThrowingStream<DeliveredTextEdit, any Error>.Continuation
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        var baseline = initialBaseline
        var pendingValue = initialBaseline
        var pendingSince: ContinuousClock.Instant?

        while !Task.isCancelled, clock.now < deadline {
            do {
                try await Task.sleep(for: Self.pollInterval)
                let current = try await observedTargetValue(receipt: receipt)
                if current != pendingValue {
                    pendingValue = current
                    pendingSince = clock.now
                    continue
                }
                guard pendingValue != baseline, let stableSince = pendingSince else { continue }
                guard stableSince.duration(to: clock.now) >= Self.debounceDuration else { continue }
                if let edit = minimalObservedDeliveredTextEdit(
                    original: baseline,
                    corrected: pendingValue,
                    deliveredText: deliveredText,
                    applicationName: receipt.context.applicationName,
                    bundleIdentifier: receipt.context.bundleIdentifier
                ) {
                    continuation.yield(edit)
                }
                baseline = pendingValue
                pendingSince = nil
            } catch is CancellationError {
                break
            } catch {
                break
            }
        }
        continuation.finish()
        finishObservation(generation: generation)
    }

    private func finishObservation(generation: UUID) {
        guard observationGeneration == generation else { return }
        observationTask = nil
        continuation = nil
        observationGeneration = nil
    }
}

private func observedTargetValue(receipt: TextDeliveryReceipt) async throws -> String {
    try await MainActor.run {
        guard !IsSecureEventInputEnabled() else { throw LerroError.secureField }
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              targetIdentityMatches(
                processIdentifier: frontmost.processIdentifier,
                bundleIdentifier: frontmost.bundleIdentifier,
                context: receipt.context
              ) else {
            throw LerroError.insertionFailed("焦点已离开原输入应用")
        }
        let systemWide = AXUIElementCreateSystemWide()
        guard let focusedApplication = observedAXElement(
            from: systemWide,
            attribute: kAXFocusedApplicationAttribute as CFString
        ), let focusedElement = observedAXElement(
            from: focusedApplication,
            attribute: kAXFocusedUIElementAttribute as CFString
        ) else {
            throw LerroError.insertionFailed("当前编辑器不支持修正观察")
        }
        var processIdentifier: pid_t = 0
        guard AXUIElementGetPid(focusedApplication, &processIdentifier) == .success,
              targetIdentityMatches(
                processIdentifier: processIdentifier,
                bundleIdentifier: NSRunningApplication(
                    processIdentifier: processIdentifier
                )?.bundleIdentifier,
                context: receipt.context
              ) else {
            throw LerroError.insertionFailed("焦点已离开原输入应用")
        }
        guard !observedAXElementIsSecure(focusedElement) else { throw LerroError.secureField }
        guard let expectedElement = receipt.focusedElementFingerprint,
              Int(CFHash(focusedElement)) == expectedElement else {
            throw LerroError.insertionFailed("焦点已离开原输入框")
        }
        guard let value = observedAXString(
            from: focusedElement,
            attribute: kAXValueAttribute as CFString
        ), (value as NSString).length <= AccessibilityDeliveredTextObserver.maximumObservedUTF16Length else {
            throw LerroError.insertionFailed("当前编辑器不支持修正观察")
        }
        return value
    }
}

func minimalObservedDeliveredTextEdit(
    original: String,
    corrected: String,
    deliveredText: String,
    applicationName: String,
    bundleIdentifier: String?,
    beforeLimit: Int = 80,
    afterLimit: Int = 40
) -> DeliveredTextEdit? {
    let originalNSString = original as NSString
    let deliveredRange = originalNSString.range(of: deliveredText)
    guard deliveredRange.location != NSNotFound,
          originalNSString.range(
            of: deliveredText,
            options: [],
            range: NSRange(
                location: NSMaxRange(deliveredRange),
                length: originalNSString.length - NSMaxRange(deliveredRange)
            )
          ).location == NSNotFound else {
        return nil
    }
    guard let diff = minimalUTF16Diff(original: original, corrected: corrected),
          NSIntersectionRange(diff.originalRange, deliveredRange).length > 0
            || (diff.originalRange.length == 0
                && diff.originalRange.location >= deliveredRange.location
                && diff.originalRange.location <= NSMaxRange(deliveredRange)) else {
        return nil
    }
    let correctedNSString = corrected as NSString
    let beforeStart = max(0, diff.correctedRange.location - max(0, beforeLimit))
    let afterStart = NSMaxRange(diff.correctedRange)
    let afterLength = min(max(0, afterLimit), correctedNSString.length - afterStart)
    let contextBefore = correctedNSString.substring(
        with: NSRange(location: beforeStart, length: diff.correctedRange.location - beforeStart)
    )
    let contextAfter = correctedNSString.substring(
        with: NSRange(location: afterStart, length: afterLength)
    )
    return DeliveredTextEdit(
        originalSpan: originalNSString.substring(with: diff.originalRange),
        correctedSpan: correctedNSString.substring(with: diff.correctedRange),
        contextBefore: contextBefore.isEmpty ? nil : contextBefore,
        contextAfter: contextAfter.isEmpty ? nil : contextAfter,
        applicationName: applicationName,
        bundleIdentifier: bundleIdentifier
    )
}

private func minimalUTF16Diff(
    original: String,
    corrected: String
) -> (originalRange: NSRange, correctedRange: NSRange)? {
    guard original != corrected else { return nil }
    let old = Array(original.utf16)
    let new = Array(corrected.utf16)
    var prefix = 0
    while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] {
        prefix += 1
    }
    var suffix = 0
    while suffix < old.count - prefix,
          suffix < new.count - prefix,
          old[old.count - suffix - 1] == new[new.count - suffix - 1] {
        suffix += 1
    }
    return (
        NSRange(location: prefix, length: old.count - prefix - suffix),
        NSRange(location: prefix, length: new.count - prefix - suffix)
    )
}

private func targetIdentityMatches(
    processIdentifier: pid_t,
    bundleIdentifier: String?,
    context: CapturedContext
) -> Bool {
    var hasIdentity = false
    if let expectedPID = context.processIdentifier {
        hasIdentity = true
        guard processIdentifier == expectedPID else { return false }
    }
    if let expectedBundle = context.bundleIdentifier {
        hasIdentity = true
        guard bundleIdentifier == expectedBundle else { return false }
    }
    return hasIdentity
}

private func observedAXElement(from element: AXUIElement, attribute: CFString) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
          let value,
          CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return unsafeDowncast(value, to: AXUIElement.self)
}

private func observedAXString(from element: AXUIElement, attribute: CFString) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
    return decodedAXTextValue(value)
}

private func observedAXElementIsSecure(_ element: AXUIElement) -> Bool {
    let role = observedAXString(from: element, attribute: kAXRoleAttribute as CFString)
    let subrole = observedAXString(from: element, attribute: kAXSubroleAttribute as CFString)
    return role == (kAXSecureTextFieldSubrole as String)
        || subrole == (kAXSecureTextFieldSubrole as String)
}
