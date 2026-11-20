# Design

## Context

动机见 `proposal.md`，验收场景见 `specs/launcher-app-search/spec.md`。`LauncherSearchViewModel` 负责查询、结果排序、选择和应用索引刷新，`LauncherPanelController` 统一处理键盘和点击执行，`LauncherView` 已提供结果行与状态区域。`InvokerSettingsView` 的通用页和 `TranslationSecretFileStore` 提供现成的配置入口与本机 JSON 保存机制。

## Goals / Non-Goals

**Goals**

- 将求值、报价和复制接入已有的启动器交互，保留普通匹配结果的排序和选择规则。
- 使用一个专用的汇率请求入口和同一份密钥配置，兼容现有用户的翻译设置。

**Non-Goals**

首版的输入范围限定为四则算式和 `$` 金额，货币对固定为 `USD/CNY`。报价只在使用美元换算时按需取得。

## Decisions

### 1. 在同一列表展示可复制结果

在 `LauncherSearchResult` 增加计算结果类型，携带显示内容与纯数字复制内容。`LauncherSearchViewModel` 完成现有应用及命令的排序后，把当前计算结果放到首行。查询变更继续选中新首行，异步报价到达时沿用选择协调逻辑，保留仍有效的当前选择，没有有效选择时选首行。等待、缺 Key 和失败用结果区文本提示呈现，提示不参与选择，普通匹配项仍可交互。

键盘与点击复用 `LauncherPanelController` 的执行入口。复制分支通过 `NSPasteboard` 写入当前可见数值，成功后关闭面板。这样既能与现有结果行共用点击和键盘行为，也能避免进入应用启动错误提示和频次统计。输入法正在编辑标记文本时仍由输入法优先处理回车。

### 2. 限定本机可计算的输入

在启动器内解析完整的四则表达式，按括号、乘除、加减的顺序求值。使用十进制数进行基础计算和金额舍入。至少识别一个二元运算符才生成算术结果，拒绝除零或不可表示的结果，以保留纯数字和无效算式的现有搜索行为。

美元输入识别为 `$` 紧随非负数字，允许以 `.` 分隔小数部分以及查询首尾空白。将金额乘以报价，按分四舍五入。结果行显示 `¥` 和两位小数，复制同一金额的数字部分，不含货币符号或分组分隔符。

### 3. 共享配置文件，按需请求一个货币对

在「设置 → 通用 → 汇率」用 SwiftUI `SecureField` 绑定 `twelve_data_api_key`。由同一设置状态读写 `~/.invoker/config.json`，每次保存携带现有 AI、DeepL 和 Twelve Data 字段，避免多个写入方用各自的旧快照覆盖密钥。用现有原子写入、目录 `0700` 和文件 `0600` 机制。不在 `UserDefaults` 保存密钥。缺少新字段按空值处理。

客户端通过 `URLSession` 向 Twelve Data 的 `/exchange_rate?symbol=USD%2FCNY` 发起 HTTPS 请求，在 `Authorization: apikey …` 请求头中认证。校验响应属于 `USD/CNY`，并含正数汇率及有效报价时间。对认证、额度和网络失败使用简短的本地提示，避免将请求头或原始错误载荷带入界面及日志。金额和普通查询保留在本机。

同一个 Key 的成功报价在内存中以获取时间为准复用 60 秒。连续修改金额时复用正在进行的货币对请求，返回后根据当前输入计算。切换到普通查询或关闭面板后不得更新可见结果或重开面板。更换或清除 Key 时使旧报价及旧请求失效。副标题显示供应商给出的报价时间，按系统时区格式化，便于识别休市时的最后可用报价。

## Risks / Trade-offs

- 报价时间受 Twelve Data 数据更新时间和休市影响。显示报价时间，定期更新由用户再次发起换算触发。
- 官方套餐文档列出 Basic 的外汇报价能力。验收时用用户自己的 Basic Key 确认该货币对的最新报价可用性。对外分发前核对 Twelve Data 对展示和使用的约定。 [Basic 套餐](https://twelvedata.com/pricing) · [USD/CNY](https://twelvedata.com/markets/573879/forex/usd-cny) · [使用条款](https://twelvedata.com/terms)
- `config.json` 沿用翻译的明文密钥存储。文件权限隔离本机其他用户，同一账号下的软件仍可能读取。请求端使用供应商推荐的认证头。 [认证文档](https://twelvedata.com/docs/introduction/libraries#authentication)

## Migration Plan

用户升级后可直接继续使用原配置。第一次在设置填写 Key 时，通过原保存流程写入新增字段。旧版读取配置时会忽略该字段，若再由旧版重新保存密钥，重新升级后可能需要再次填写 Twelve Data Key。
