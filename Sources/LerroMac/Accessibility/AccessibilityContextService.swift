import AppKit
import ApplicationServices
import Carbon
import Foundation
import LerroCore

public struct AccessibilityContextService: ContextCapturing {
    public init() {}

    public func captureCurrentContext() async -> CapturedContext {
        await MainActor.run {
            let application = NSWorkspace.shared.frontmostApplication
            var appName = application?.localizedName ?? "Unknown"
            var processIdentifier = application?.processIdentifier
            var bundleIdentifier = application?.bundleIdentifier
            let secureInputEnabled = IsSecureEventInputEnabled()

            let systemWide = AXUIElementCreateSystemWide()
            guard let focusedApplication: AXUIElement = copyElement(
                from: systemWide,
                attribute: kAXFocusedApplicationAttribute as CFString
            ) else {
                return CapturedContext(
                    applicationName: appName,
                    processIdentifier: processIdentifier,
                    bundleIdentifier: bundleIdentifier,
                    isSecureField: secureInputEnabled
                )
            }
            var focusedProcessIdentifier: pid_t = 0
            if AXUIElementGetPid(focusedApplication, &focusedProcessIdentifier) == .success {
                processIdentifier = focusedProcessIdentifier
                if let focusedApplication = NSRunningApplication(
                    processIdentifier: focusedProcessIdentifier
                ) {
                    appName = focusedApplication.localizedName ?? appName
                    bundleIdentifier = focusedApplication.bundleIdentifier ?? bundleIdentifier
                }
            }

            let focusedElement: AXUIElement? = copyElement(
                from: focusedApplication,
                attribute: kAXFocusedUIElementAttribute as CFString
            )
            let focusedWindow: AXUIElement? = copyElement(
                from: focusedApplication,
                attribute: kAXFocusedWindowAttribute as CFString
            )

            let role = focusedElement.flatMap { copyString(from: $0, attribute: kAXRoleAttribute as CFString) }
            let subrole = focusedElement.flatMap {
                copyString(from: $0, attribute: kAXSubroleAttribute as CFString)
            }
            let isSecureField = secureInputEnabled
                || role == (kAXSecureTextFieldSubrole as String)
                || subrole == (kAXSecureTextFieldSubrole as String)
            let selection = isSecureField
                ? (state: TextSelectionState.unavailable, text: nil)
                : selectionObservation(from: focusedElement)
            let completeSelectedText = selection.text
            let selectedText = completeSelectedText.map {
                String($0.prefix(CapturedContext.maximumSelectedTextCharacters))
            }
            let completeFocusedText = isSecureField
                ? nil
                : focusedElement.flatMap {
                    copyString(from: $0, attribute: kAXValueAttribute as CFString)
                }
            let selectedRange = isSecureField
                ? nil
                : focusedElement.flatMap {
                    copyRange(from: $0, attribute: kAXSelectedTextRangeAttribute as CFString)
                }
            let cursorNeighborhood = completeFocusedText.flatMap {
                resolvedCursorNeighborhood(text: $0, selectedRange: selectedRange)
            }
            let focusedText = completeFocusedText.map { String($0.prefix(2_048)) }
            let windowTitle = focusedWindow.flatMap { copyString(from: $0, attribute: kAXTitleAttribute as CFString) }

            return CapturedContext(
                applicationName: appName,
                processIdentifier: processIdentifier,
                bundleIdentifier: bundleIdentifier,
                windowTitle: windowTitle,
                selectedText: selectedText?.isEmpty == true ? nil : selectedText,
                selectedTextWasTruncated: completeSelectedText.map {
                    $0.count > CapturedContext.maximumSelectedTextCharacters
                } ?? false,
                selectedTextFingerprint: completeSelectedText?.isEmpty == false
                    ? completeSelectedText?.hashValue
                    : nil,
                selectionState: selection.state,
                focusedText: focusedText?.isEmpty == true ? nil : focusedText,
                cursorBefore: cursorNeighborhood?.before,
                cursorAfter: cursorNeighborhood?.after,
                role: role,
                subrole: subrole,
                isSecureField: isSecureField,
                focusedElementAvailable: focusedElement != nil,
                focusedElementFingerprint: isSecureField
                    ? nil
                    : focusedElement.map { Int(CFHash($0)) },
                focusedValueFingerprint: isSecureField
                    ? nil
                    : completeFocusedText?.hashValue,
                selectedRange: selectedRange.map {
                    UTF16TextRange(location: $0.location, length: $0.length)
                }
            )
        }
    }
}

func resolvedCursorNeighborhood(
    text: String,
    selectedRange: CFRange?,
    beforeLimit: Int = 80,
    afterLimit: Int = 40
) -> (before: String?, after: String?) {
    guard let selectedRange else { return (nil, nil) }
    let value = text as NSString
    let location = min(max(0, selectedRange.location), value.length)
    let selectionLength = min(max(0, selectedRange.length), value.length - location)
    let beforeLength = min(max(0, beforeLimit), location)
    let afterStart = location + selectionLength
    let afterLength = min(max(0, afterLimit), value.length - afterStart)

    let before = beforeLength > 0
        ? value.substring(with: NSRange(location: location - beforeLength, length: beforeLength))
        : nil
    let after = afterLength > 0
        ? value.substring(with: NSRange(location: afterStart, length: afterLength))
        : nil
    return (before, after)
}

private func selectionObservation(
    from element: AXUIElement?
) -> (state: TextSelectionState, text: String?) {
    guard let element else { return (.unavailable, nil) }
    let selectedText = copyString(
        from: element,
        attribute: kAXSelectedTextAttribute as CFString
    )
    let selectedRange = copyRange(
        from: element,
        attribute: kAXSelectedTextRangeAttribute as CFString
    )
    return (
        resolvedTextSelectionState(
            selectedText: selectedText,
            selectedRange: selectedRange
        ),
        selectedText
    )
}

func resolvedTextSelectionState(
    selectedText: String?,
    selectedRange: CFRange?
) -> TextSelectionState {
    if selectedText?.isEmpty == false { return .knownSelection }
    if let selectedRange {
        return selectedRange.length == 0 ? .knownEmpty : .knownSelection
    }
    if let selectedText {
        return selectedText.isEmpty ? .knownEmpty : .knownSelection
    }
    return .unavailable
}

private func copyElement(from element: AXUIElement, attribute: CFString) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
          let value,
          CFGetTypeID(value) == AXUIElementGetTypeID() else {
        return nil
    }
    return unsafeDowncast(value, to: AXUIElement.self)
}

private func copyString(from element: AXUIElement, attribute: CFString) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
        return nil
    }
    return decodedAXTextValue(value)
}

func decodedAXTextValue(_ value: CFTypeRef?) -> String? {
    if let string = value as? String { return string }
    if let attributed = value as? NSAttributedString { return attributed.string }
    return nil
}

private func copyRange(from element: AXUIElement, attribute: CFString) -> CFRange? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
          let value,
          CFGetTypeID(value) == AXValueGetTypeID() else {
        return nil
    }
    let axValue = unsafeDowncast(value, to: AXValue.self)
    var range = CFRange()
    guard AXValueGetType(axValue) == .cfRange,
          AXValueGetValue(axValue, .cfRange, &range),
          range.location >= 0,
          range.length >= 0 else {
        return nil
    }
    return range
}
