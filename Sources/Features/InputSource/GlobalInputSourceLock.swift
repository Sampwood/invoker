import Carbon
import Foundation

final class GlobalInputSourceLock: NSObject {
    private let targetInputSourceIDs = [
        "com.sogou.inputmethod.sogou.pinyin",
        "com.sogou.inputmethod.sogou.pinyin.ime"
    ]
    private let targetLocalizedNames = [
        "搜狗拼音",
        "搜狗输入法",
        "Sogou Pinyin"
    ]

    private var isSelectingTarget = false

    func start() {
        lockToTargetInputSource()

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceDidChange(_:)),
            name: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(enabledInputSourcesDidChange(_:)),
            name: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
            object: nil
        )
    }

    func stop() {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func inputSourceDidChange(_ notification: Notification) {
        guard !isSelectingTarget else {
            return
        }

        lockToTargetInputSource()
    }

    @objc private func enabledInputSourcesDidChange(_ notification: Notification) {
        lockToTargetInputSource()
    }

    private func lockToTargetInputSource() {
        guard currentInputSourceIsTarget() != true else {
            return
        }
        guard let target = targetInputSource() else {
            NSLog("Invoker could not find the Sogou Pinyin input source.")
            return
        }

        isSelectingTarget = true
        let status = TISSelectInputSource(target)
        isSelectingTarget = false

        if status != noErr {
            NSLog("Invoker failed to select Sogou Pinyin input source: \(status).")
        }
    }

    private func targetInputSource() -> TISInputSource? {
        let enabledSources = inputSources()

        if let source = enabledSources.first(where: { source in
            inputSourceID(source).map(isTargetInputSourceID) == true
        }) {
            return source
        }

        if let source = enabledSources.first(where: { source in
            localizedName(source).map(isTargetLocalizedName) == true
        }) {
            return source
        }

        return nil
    }

    private func inputSources() -> [TISInputSource] {
        guard let unmanagedSources = TISCreateInputSourceList(nil, false) else {
            return []
        }

        return unmanagedSources.takeRetainedValue() as? [TISInputSource] ?? []
    }

    private func currentInputSourceIsTarget() -> Bool? {
        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }

        return inputSourceID(currentSource).map(isTargetInputSourceID) == true
            || localizedName(currentSource).map(isTargetLocalizedName) == true
    }

    private func inputSourceID(_ source: TISInputSource) -> String? {
        stringProperty(kTISPropertyInputSourceID, from: source)
    }

    private func localizedName(_ source: TISInputSource) -> String? {
        stringProperty(kTISPropertyLocalizedName, from: source)
    }

    private func stringProperty(_ key: CFString, from source: TISInputSource) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else {
            return nil
        }

        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private func isTargetInputSourceID(_ inputSourceID: String) -> Bool {
        targetInputSourceIDs.contains(inputSourceID)
    }

    private func isTargetLocalizedName(_ localizedName: String) -> Bool {
        targetLocalizedNames.contains { targetName in
            localizedName.localizedCaseInsensitiveContains(targetName)
        }
    }
}
