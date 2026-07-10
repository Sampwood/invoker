struct StatusBarMenuItemContent: Equatable {
    let title: String
}

enum StatusBarMenuContent {
    static let items = [
        StatusBarMenuItemContent(title: "截图"),
        StatusBarMenuItemContent(title: "检查更新..."),
        StatusBarMenuItemContent(title: "退出 Invoker")
    ]
}
