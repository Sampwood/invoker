import AppKit
import ApplicationServices
import Foundation

@MainActor
protocol SelectedTextReading: AnyObject {
    func selectedText(promptForPermission: Bool) throws -> String
    func openAccessibilitySettings()
}

@MainActor
final class AccessibilitySelectedTextReader: SelectedTextReading {
    private static let maximumAncestorDepth = 12

    func selectedText(promptForPermission: Bool) throws -> String {
        let options = ["AXTrustedCheckOptionPrompt": promptForPermission] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            throw TranslationError.accessibilityPermissionRequired
        }

        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        guard focusedStatus == .success, let focusedValue else {
            throw TranslationError.noSelectedText
        }

        let focusedElement = focusedValue as! AXUIElement
        var currentElement: AXUIElement? = focusedElement
        for _ in 0..<Self.maximumAncestorDepth {
            guard let element = currentElement else {
                break
            }
            if let text = selectedTextValue(from: element) {
                return text
            }
            currentElement = parent(of: element)
        }

        throw TranslationError.noSelectedText
    }

    private func selectedTextValue(from element: AXUIElement) -> String? {
        var selectedValue: CFTypeRef?
        let selectedStatus = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedValue
        )
        if selectedStatus == .success, let text = text(from: selectedValue) {
            return text
        }

        return webSelectedTextValue(from: element)
    }

    private func webSelectedTextValue(from element: AXUIElement) -> String? {
        var markerRange: CFTypeRef?
        let markerStatus = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextMarkerRangeAttribute as CFString,
            &markerRange
        )
        guard markerStatus == .success, let markerRange else {
            return nil
        }

        var selectedValue: CFTypeRef?
        let selectedStatus = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForTextMarkerRangeParameterizedAttribute as CFString,
            markerRange,
            &selectedValue
        )
        guard selectedStatus == .success else {
            return nil
        }

        return text(from: selectedValue)
    }

    private func parent(of element: AXUIElement) -> AXUIElement? {
        var parentValue: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            element,
            kAXParentAttribute as CFString,
            &parentValue
        )
        guard status == .success,
              let parentValue,
              CFGetTypeID(parentValue) == AXUIElementGetTypeID()
        else {
            return nil
        }

        return parentValue as! AXUIElement
    }

    private func text(from value: CFTypeRef?) -> String? {
        let text: String?
        if let string = value as? String {
            text = string
        } else if let attributedString = value as? NSAttributedString {
            text = attributedString.string
        } else {
            text = nil
        }

        guard let text,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return text
    }

    func openAccessibilitySettings() {
        let paths = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ]
        for path in paths {
            if let url = URL(string: path), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}
