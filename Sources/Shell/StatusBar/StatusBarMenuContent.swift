struct StatusBarMenuItemContent: Equatable {
    let title: String
}

enum StatusBarMenuContent {
    static let items = [
        StatusBarMenuItemContent(title: "退出 Invoker")
    ]
}
