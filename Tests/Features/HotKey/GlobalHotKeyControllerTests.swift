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
