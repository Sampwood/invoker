struct StatusBarMenuItemContent: Equatable {
    let title: String
}

enum StatusBarMenuContent {
    static let items = [
        StatusBarMenuItemContent(title: "翻译..."),
        StatusBarMenuItemContent(title: "截图"),
        StatusBarMenuItemContent(title: "剪贴板历史"),
        StatusBarMenuItemContent(title: "设置..."),
        StatusBarMenuItemContent(title: "检查更新..."),
        StatusBarMenuItemContent(title: "退出 Invoker")
    ]
}
