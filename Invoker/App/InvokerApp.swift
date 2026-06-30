import AppKit

@main
struct InvokerApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()

        application.delegate = delegate
        application.run()
    }
}
