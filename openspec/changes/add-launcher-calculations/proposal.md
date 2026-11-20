# Proposal

## Why

用户希望在 Option + Space 启动器中直接算出 `100*2`，或输入 `$1` 查美元折合多少人民币。两种操作都可以沿用搜索框、结果行和回车交互，省去切换应用。

## What Changes

- 在输入完整四则算式后即时显示本地计算结果，例如 `100*2` 显示 `200`。支持括号和小数。
- 将 `$` 加金额识别为美元转人民币。按需从 Twelve Data 获取最新可用的 `USD/CNY` 报价，本地计算并显示两位小数的人民币金额及报价时间。
- 在「设置 → 通用 → 汇率」提供遮挡输入框，由用户填写自己的 Twelve Data API Key。沿用翻译的本机密钥配置方式。
- 两类计算结果均排在匹配的命令和应用之前。选中结果按回车或点击时，复制金额数字或算术结果并关闭启动器。

## Capabilities

### New Capabilities

### Modified Capabilities

- `launcher-app-search` 提供算术和汇率换算结果，并扩展结果区状态及执行行为。

## Impact

- 启动器结果模型、搜索状态、现有结果行与执行入口增加计算结果和汇率状态。
- 在现有设置窗口和 `~/.invoker/config.json` 中新增独立的 Twelve Data Key 字段，旧配置继续可读。
- 唯一新增外部服务是 Twelve Data 的汇率接口。普通搜索和算术仍在本机执行。
- `launcher-liquid-glass` 的玻璃布局用于呈现新增结果及状态。该视觉变更的独立验收照原计划进行。
