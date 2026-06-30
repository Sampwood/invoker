# macOS 菜单栏日历 MVP 可执行计划

## Summary
目标是在空 git 仓库中初始化一个 Swift 原生 macOS 应用，第一版只交付“菜单栏日历 MVP”。

确认范围：
- 应用仅出现在 macOS 顶部菜单栏，不显示 Dock 图标和主窗口。
- 点击菜单栏日历 icon 后显示下拉日历。
- 日历支持当前月展示、上一月/下一月切换、今天高亮、选中日期、“今天”快捷回跳。
- 不接入系统日历、不读取事件、不做本地备注。
- 截屏、截长屏、AI 翻译窗口作为后续里程碑，不进入本次实现。

技术选择：
- Xcode macOS App 工程。
- Swift 6 / SwiftUI App lifecycle。
- 最低支持 macOS 13+。
- 使用 SwiftUI `MenuBarExtra` 实现菜单栏入口。
- 使用 `LSUIElement` 配置为菜单栏常驻应用。
- 日历计算逻辑独立于 UI，便于单元测试。

## Key Changes
1. 初始化 `Invoker.xcodeproj`，包含 `Invoker` app target 和 `InvokerTests` test target。
2. 使用 `MenuBarExtra` 作为唯一入口，并通过 `LSUIElement = YES` 设为菜单栏应用。
3. 实现 `CalendarDay`、`CalendarMonthGrid`、`CalendarViewModel`，生成固定 6x7 月历网格。
4. 实现紧凑 SwiftUI 日历下拉 UI。
5. 后续截图、截长屏、AI 翻译窗口作为独立计划处理。

## Test Plan
1. 单元测试月历网格：6x7、当前月天数、相邻月补齐、跨年、闰年二月、非闰年二月。
2. 单元测试状态行为：上一月、下一月、回到今天、日期选择、今天高亮、选中态。
3. 构建验证：`xcodebuild test` 和 `xcodebuild build`。
4. 手动验收：菜单栏 icon、无 Dock 图标、下拉日历、月份切换、Today、日期选中。

## Assumptions
- 产品名为 `Invoker`。
- Bundle Identifier 为 `com.sampwood.invoker`。
- 第一版仅支持 macOS 13+。
- 第一版不支持系统日历事件、提醒事项、本地备注、登录启动设置、周起始日自定义、主题设置。
- 第一版不实现截图、截长屏、AI 翻译窗口。
- UI 文案第一版使用英文短标签。
