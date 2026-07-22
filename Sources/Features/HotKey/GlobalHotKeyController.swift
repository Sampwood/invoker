import Carbon
import Foundation

struct GlobalHotKeyConfiguration: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let identifier: EventHotKeyID
    let displayName: String
    let shortcutDescription: String

    static let screenshot = GlobalHotKeyConfiguration(
        keyCode: UInt32(kVK_ANSI_X),
        modifiers: UInt32(cmdKey | shiftKey),
        identifier: EventHotKeyID(signature: OSType(0x494E_564B), id: UInt32(1)),
        displayName: "截图",
        shortcutDescription: "Shift + Command + X"
    )

    static let selectionTranslation = GlobalHotKeyConfiguration(
        keyCode: UInt32(kVK_ANSI_F),
        modifiers: UInt32(optionKey),
        identifier: EventHotKeyID(signature: OSType(0x494E_564B), id: UInt32(2)),
        displayName: "翻译",
        shortcutDescription: "Option + F"
    )

    static let clipboardHistory = GlobalHotKeyConfiguration(
        keyCode: UInt32(kVK_ANSI_V),
        modifiers: UInt32(cmdKey | shiftKey),
        identifier: EventHotKeyID(signature: OSType(0x494E_564B), id: UInt32(3)),
        displayName: "剪贴板历史",
        shortcutDescription: "Shift + Command + V"
    )

    static func == (lhs: GlobalHotKeyConfiguration, rhs: GlobalHotKeyConfiguration) -> Bool {
        lhs.keyCode == rhs.keyCode
            && lhs.modifiers == rhs.modifiers
            && lhs.identifier.signature == rhs.identifier.signature
            && lhs.identifier.id == rhs.identifier.id
            && lhs.displayName == rhs.displayName
            && lhs.shortcutDescription == rhs.shortcutDescription
    }
}

enum GlobalHotKeyRegistrationError: LocalizedError, Equatable, Sendable {
    case eventHandlerInstallFailed(OSStatus)
    case hotKeyRegistrationFailed(OSStatus, shortcutDescription: String)

    var errorDescription: String? {
        switch self {
        case let .eventHandlerInstallFailed(status):
            return "无法安装快捷键事件处理器，错误码：\(status)。"
        case let .hotKeyRegistrationFailed(status, shortcutDescription):
            return "无法注册 \(shortcutDescription)，错误码：\(status)。"
        }
    }
}

@MainActor
final class GlobalHotKeyController {
    private let configuration: GlobalHotKeyConfiguration
    private let action: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    init(
        configuration: GlobalHotKeyConfiguration = .screenshot,
        action: @escaping () -> Void
    ) {
        self.configuration = configuration
        self.action = action
    }

    var isRegistered: Bool {
        hotKeyRef != nil
    }

    func register() throws {
        guard hotKeyRef == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let eventHandlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            globalHotKeyEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        guard eventHandlerStatus == noErr else {
            throw GlobalHotKeyRegistrationError.eventHandlerInstallFailed(eventHandlerStatus)
        }

        let registrationStatus = RegisterEventHotKey(
            configuration.keyCode,
            configuration.modifiers,
            configuration.identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registrationStatus == noErr else {
            unregister()
            throw GlobalHotKeyRegistrationError.hotKeyRegistrationFailed(
                registrationStatus,
                shortcutDescription: configuration.shortcutDescription
            )
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    func handleHotKeyIdentifier(_ identifier: EventHotKeyID) -> OSStatus {
        handleHotKeyIdentifier(signature: identifier.signature, id: identifier.id)
    }

    func handleHotKeyIdentifier(signature: OSType, id: UInt32) -> OSStatus {
        guard signature == configuration.identifier.signature,
              id == configuration.identifier.id else {
            return OSStatus(eventNotHandledErr)
        }

        action()
        return noErr
    }
}

private func globalHotKeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else {
        return OSStatus(eventNotHandledErr)
    }
    let result = hotKeyIdentifier(from: event)
    guard result.status == noErr, let identifier = result.identifier else {
        return result.status
    }
    let signature = identifier.signature
    let id = identifier.id

    let controller = Unmanaged<GlobalHotKeyController>
        .fromOpaque(userData)
        .takeUnretainedValue()

    return MainActor.assumeIsolated {
        controller.handleHotKeyIdentifier(
            signature: signature,
            id: id
        )
    }
}

private func hotKeyIdentifier(from event: EventRef?) -> (status: OSStatus, identifier: EventHotKeyID?) {
    guard let event else {
        return (OSStatus(eventNotHandledErr), nil)
    }

    var identifier = EventHotKeyID(signature: OSType(0), id: UInt32(0))
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &identifier
    )
    guard status == noErr else {
        return (status, nil)
    }

    return (noErr, identifier)
}
