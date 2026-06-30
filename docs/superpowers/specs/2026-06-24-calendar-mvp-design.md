# macOS 菜单栏日历 MVP 设计说明

## Product Boundary
Invoker MVP 是一个仅菜单栏应用。启动后不显示 Dock 图标和主窗口，菜单栏显示日历图标。点击图标打开紧凑下拉日历，支持当前月展示、前后月切换、今天高亮、选中日期和回到今天。

第一版不接入系统日历，不读取事件，不保存本地备注。截图、截长屏和 AI 翻译窗口留作后续独立里程碑。

## Architecture
应用使用 SwiftUI App lifecycle 和 `MenuBarExtra`。日历计算逻辑放在 view model 与模型中，SwiftUI view 只负责渲染与交互。

最低支持 macOS 13。应用通过 `LSUIElement = YES` 以菜单栏常驻形态运行。

## Acceptance
- 构建后应用只出现在菜单栏。
- 点击菜单栏图标显示日历下拉区域。
- 月份切换、日期选择、今天高亮和 Today 回跳行为正确。
- 单元测试覆盖月历网格和状态行为。
