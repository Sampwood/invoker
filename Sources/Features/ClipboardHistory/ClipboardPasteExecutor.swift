import AppKit
import ApplicationServices
import Carbon

enum ClipboardPasteResult: Equatable {
    case pasted
    case accessibilityPermissionRequired
    case failed
}

@MainActor
final class ClipboardPasteExecutor {
    private var targetApplication: NSRunningApplication?

    func rememberFrontmostApplication() {
        targetApplication = NSWorkspace.shared.frontmostApplication
    }

    func pasteToRememberedApplication(promptForPermission: Bool = true) -> ClipboardPasteResult {
        let options = ["AXTrustedCheckOptionPrompt": promptForPermission] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            return .accessibilityPermissionRequired
        }

        targetApplication?.activate(options: [.activateIgnoringOtherApps])
        guard Self.postPasteShortcut() else {
            return .failed
        }

        return .pasted
    }

    private static func postPasteShortcut() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: false
              )
        else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
