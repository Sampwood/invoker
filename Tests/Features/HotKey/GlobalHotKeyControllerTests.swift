import Carbon
import XCTest
@testable import Invoker

@MainActor
final class GlobalHotKeyControllerTests: XCTestCase {
    func testScreenshotHotKeyUsesShiftCommandX() {
        let configuration = GlobalHotKeyConfiguration.screenshot

        XCTAssertEqual(configuration.keyCode, UInt32(kVK_ANSI_X))
        XCTAssertEqual(configuration.modifiers, UInt32(cmdKey | shiftKey))
        XCTAssertEqual(configuration.identifier.signature, 0x494E_564B)
        XCTAssertEqual(configuration.identifier.id, 1)
    }

    func testSelectionTranslationHotKeyUsesOptionFAndUniqueIdentifier() {
        let configuration = GlobalHotKeyConfiguration.selectionTranslation

        XCTAssertEqual(configuration.keyCode, UInt32(kVK_ANSI_F))
        XCTAssertEqual(configuration.modifiers, UInt32(optionKey))
        XCTAssertEqual(configuration.identifier.signature, 0x494E_564B)
        XCTAssertEqual(configuration.identifier.id, 2)
        XCTAssertNotEqual(configuration.identifier.id, GlobalHotKeyConfiguration.screenshot.identifier.id)
    }

    func testClipboardHistoryHotKeyUsesShiftCommandVAndUniqueIdentifier() {
        let configuration = GlobalHotKeyConfiguration.clipboardHistory

        XCTAssertEqual(configuration.keyCode, UInt32(kVK_ANSI_V))
        XCTAssertEqual(configuration.modifiers, UInt32(cmdKey | shiftKey))
        XCTAssertEqual(configuration.identifier.signature, 0x494E_564B)
        XCTAssertEqual(configuration.identifier.id, 3)
        XCTAssertNotEqual(configuration.identifier.id, GlobalHotKeyConfiguration.screenshot.identifier.id)
        XCTAssertNotEqual(configuration.identifier.id, GlobalHotKeyConfiguration.selectionTranslation.identifier.id)
    }

    func testMatchingHotKeyIdentifierInvokesAction() {
        var invocationCount = 0
        let controller = GlobalHotKeyController(configuration: .screenshot) {
            invocationCount += 1
        }

        let status = controller.handleHotKeyIdentifier(GlobalHotKeyConfiguration.screenshot.identifier)

        XCTAssertEqual(status, noErr)
        XCTAssertEqual(invocationCount, 1)
    }

    func testNonMatchingHotKeyIdentifierIsIgnored() {
        var invocationCount = 0
        let controller = GlobalHotKeyController(configuration: .screenshot) {
            invocationCount += 1
        }
        let otherIdentifier = EventHotKeyID(signature: OSType(0x4F54_4852), id: UInt32(99))

        let status = controller.handleHotKeyIdentifier(otherIdentifier)

        XCTAssertEqual(status, OSStatus(eventNotHandledErr))
        XCTAssertEqual(invocationCount, 0)
    }
}
