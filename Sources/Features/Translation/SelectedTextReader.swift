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
        var selectedValue: CFTypeRef?
        let selectedStatus = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &selectedValue
        )
        guard selectedStatus == .success, let selectedValue else {
            throw TranslationError.noSelectedText
        }

        let text: String?
        if let string = selectedValue as? String {
            text = string
        } else if let attributedString = selectedValue as? NSAttributedString {
            text = attributedString.string
        } else {
            text = nil
        }

        guard let text,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw TranslationError.noSelectedText
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
