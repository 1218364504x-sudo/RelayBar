# RelayBar

RelayBar 是一个 macOS 原生菜单栏应用，带悬浮窗和 WidgetKit 桌面小组件，用来查看多个 API 中转站 / New API / One API / Sub2API 兼容站点的余额和用量。

当前界面主要展示这几类指标：

- 余额
- 今日消费
- 今日 Token
- 累计 Token

项目早期名称是 `CostBar-kx`，为了减少工程改动，Xcode target、scheme 和部分目录名仍保留原名；用户可见的应用名是 RelayBar。

## 功能

- 菜单栏状态显示和详情弹窗
- 多配置档管理，每个配置档独立保存凭证
- 兼容 New API / One API / Sub2API 风格的余额和用量接口
- 支持跟随 CC Switch 当前供应商
- 支持可选悬浮窗
- 支持 Small、Medium、Large 三种 WidgetKit 小组件
- 主 App 将脱敏快照写入 App Group，小组件仅读取缓存
- API Key 只保存在 macOS Keychain

## 架构

```text
主 App
  ├─ 从 Keychain 读取凭证
  ├─ 刷新当前配置档的数据
  ├─ 将脱敏后的 PixelDashboardSnapshot 写入 App Group
  └─ 通知 WidgetKit 刷新时间线

Widget 扩展
  └─ 只读取 App Group 中的快照缓存
```

重要文件：

- `Shared/PixelDashboardSnapshot.swift`：主 App 和 Widget 共享的快照模型、App Group 缓存读写
- `ViewModels/DashboardViewModel.swift`：刷新、配置档、CC Switch 跟随、Widget 发布的主流程
- `Services/UsageServiceFactory.swift`：Pixel / New API / Sub2API 兼容数据拉取
- `Services/CCSwitchIntegrationService.swift`：可选的 CC Switch 本地数据库读取
- `PixelAPIWidget/PixelAPIWidget.swift`：WidgetKit 小组件界面

## 安全设计

- API Key 只保存到 macOS Keychain
- API Key 不写入 UserDefaults、JSON 缓存、plist、README 示例或日志
- Widget 不读取 Keychain
- Widget 不发起网络请求
- Widget 不读取 CC Switch
- Widget 只读取主 App 写入 App Group 的脱敏缓存
- App Group 缓存不得包含 `Authorization`、`Bearer`、`Cookie` 或任何原始凭证

## 环境要求

- macOS 14 或更新版本
- Xcode 16 或更新版本
- 如需运行 WidgetKit 和 App Group，需要 Apple Developer Team

## 开源项目配置

克隆或 fork 后，请先修改主 App 和 Widget 两个 target 的签名配置：

- `DEVELOPMENT_TEAM`
- `PRODUCT_BUNDLE_IDENTIFIER`
- `RELAYBAR_APP_GROUP`

具体位置见 [OPEN_SOURCE_SETUP.md](OPEN_SOURCE_SETUP.md)。

推荐命名示例：

```text
主 App Bundle ID：   com.yourname.RelayBar
Widget Bundle ID：  com.yourname.RelayBar.Widget
App Group：         TEAMID.com.yourname.relaybar.widget
```

## 运行

用 Xcode 打开 `CostBar-kx.xcodeproj`，选择 `CostBar-kx` scheme，然后运行。

也可以用命令行构建：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project CostBar-kx.xcodeproj \
  -scheme CostBar-kx \
  -configuration Debug \
  -derivedDataPath /tmp/relaybar-build \
  build
```

## 添加配置档

1. 打开 RelayBar。
2. 从菜单栏弹窗进入设置。
3. 新增或编辑一个配置档。
4. 填写站点地址和 API Key。
5. 保存后测试连接。

如果要移除已保存的凭证，请使用“清除凭证”。凭证会从 Keychain 删除，同时清理对应的缓存快照。

## 添加桌面小组件

1. 在 macOS 桌面右键。
2. 选择“编辑小组件”。
3. 搜索 RelayBar。
4. 添加 Small、Medium 或 Large 小组件。
5. 如果小组件暂无数据，先打开主 App 手动刷新一次。

## CC Switch 跟随

RelayBar 可以选择跟随 CC Switch 当前供应商。

支持两种模式：

- 只读状态：仅读取当前供应商状态
- 读取状态和 Key：读取当前供应商，并将 Key 写入 RelayBar 自己的 Keychain

CC Switch 只由主 App 读取。Widget 不会直接读取 CC Switch，也不会读取任何凭证。

## 发布前检查

发布前建议运行：

```bash
rg -n "sk-|Authorization|Bearer|Cookie|api-key" .
rg -n "DEVELOPMENT_TEAM|PRODUCT_BUNDLE_IDENTIFIER|RELAYBAR_APP_GROUP|App Group" README.md OPEN_SOURCE_SETUP.md project.yml CostBar-kx.xcodeproj/project.pbxproj
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CostBar-kx.xcodeproj -scheme CostBar-kx -configuration Debug build
```

第一条命令如果有命中，应只出现在请求头实现代码、占位符或安全说明里，不应出现真实凭证。

## 许可证

MIT，见 [LICENSE](LICENSE)。
