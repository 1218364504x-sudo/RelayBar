# 开源项目配置

RelayBar 仍保留原来的 Xcode target 名称：`CostBar-kx` 和 `PixelAPIWidget`。这样可以减少不必要的工程改动。如果你 fork 或 clone 本项目，通常只需要修改签名相关配置。

## 必填签名配置

请在 Xcode 中分别修改主 App target 和 Widget target 的 Build Settings：

- `DEVELOPMENT_TEAM`
- `PRODUCT_BUNDLE_IDENTIFIER`
- `RELAYBAR_APP_GROUP`

推荐格式：

```text
主 App Bundle ID：   com.yourname.RelayBar
Widget Bundle ID：  com.yourname.RelayBar.Widget
App Group：         TEAMID.com.yourname.relaybar.widget
```

`RELAYBAR_APP_GROUP` 会被以下文件使用：

- `CostBar-kx.entitlements`
- `PixelAPIWidget/PixelAPIWidget.entitlements`
- `Info.plist`
- `PixelAPIWidget/Info.plist`
- `Shared/PixelDashboardSnapshot.swift`

主 App 和 Widget 必须使用同一个 App Group，否则 WidgetKit 无法读取主 App 写入的共享缓存。

## XcodeGen

`project.yml` 和当前提交的 Xcode 工程保持一致。如果你使用 XcodeGen 重新生成工程，请先同步修改 `project.yml` 中的签名配置。

## 凭证和隐私

不要提交 API Key、导出的本地缓存或任何真实站点凭证。凭证只应该保存在 macOS Keychain 中。

Widget 共享缓存文件不得包含请求头、Cookie、Bearer token 或任何原始凭证。
