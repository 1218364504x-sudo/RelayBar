# RelayBar 软件说明

RelayBar 是一个 macOS 原生菜单栏应用，配套悬浮窗和 WidgetKit 桌面小组件，用于查看 API 中转站 / New API / Sub2API 兼容站点的账户余额和使用概览。

## 主要功能

- 菜单栏显示当前配置档余额和状态
- 菜单栏弹窗显示余额、今日消费、今日 Token、累计 Token
- 支持多个供应商配置档
- 每个配置档独立保存访问凭证
- 支持 CC Switch 当前供应商跟随
- 支持悬浮窗显示核心余额信息
- 支持 WidgetKit Small / Medium / Large 桌面小组件
- 支持 Codex 5h / 周剩余额度显示
- 支持本地缓存最近一次脱敏快照

## 隐私与安全

- API Key 只保存到 macOS Keychain
- 配置 JSON、UserDefaults、README、Widget 缓存均不保存 API Key
- Widget 不读取 Keychain
- Widget 不请求网络
- Widget 不读取 CC Switch
- Widget 只读取主 App 写入 App Group 的脱敏缓存
- App Group 缓存不应包含 Authorization、Bearer、Cookie 或任何凭证
- Codex 额度读取只保存剩余百分比和重置时间，不保存 Codex 登录凭证

## 快速上手

1. 使用 Xcode 16 或更新版本打开 `CostBar-kx.xcodeproj`
2. 进入主 App、Widget、Tests 三个 target 的 Build Settings
3. 修改以下值：
   - `DEVELOPMENT_TEAM`
   - `PRODUCT_BUNDLE_IDENTIFIER`
   - `RELAYBAR_APP_GROUP`
4. 选择 `CostBar-kx` Scheme 运行
5. 打开菜单栏 RelayBar 图标，进入设置页
6. 新增或编辑配置档，填写 Base URL 和访问凭证
7. 保存后点击测试连接
8. 如需显示 Codex 额度，在设置页开启“显示 Codex 剩余额度”；已安装并登录 Codex CLI 时可开启自动读取

推荐命名格式：

```text
主 App Bundle ID:  com.yourname.RelayBar
Widget Bundle ID:  com.yourname.RelayBar.Widget
App Group:         TEAMID.com.yourname.relaybar.widget
```

主 App 和 Widget 的 App Group 必须一致，否则 Widget 无法读取缓存。

## 打包说明

本源码包不包含开发者签名证书、不包含个人 Team ID、不包含任何真实站点凭证。你需要用自己的 Apple Developer Team 重新签名和归档。

命令行构建示例：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project CostBar-kx.xcodeproj \
  -scheme CostBar-kx \
  -configuration Debug \
  build
```

测试：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test -project CostBar-kx.xcodeproj \
  -scheme CostBar-kx \
  -destination 'platform=macOS'
```

## 开源前检查

发布前建议运行：

```bash
rg -n "sk-|Authorization|Bearer|Cookie|api-key" .
rg -n "HOME_PATH_PLACEHOLDER|YOUR_REAL_TEAM_ID|YOUR_REAL_BUNDLE_ID" .
```

命中应只出现在文档说明、占位符或请求头实现代码中，不应出现真实凭证。

## 项目结构

```text
CostBar-kxApp.swift                 App 入口、菜单栏、设置窗口管理
Views/                              SwiftUI UI
ViewModels/DashboardViewModel.swift 刷新、配置档、CC Switch、Widget 发布逻辑
Services/                           API 服务与 CC Switch 集成
Shared/PixelDashboardSnapshot.swift 主 App 与 Widget 共享的脱敏快照模型
PixelAPIWidget/                     WidgetKit 小组件
Storage/                            Keychain 与本地缓存
kxTests/                            单元测试
```

## License

MIT License
