# Open Source Setup

RelayBar keeps the original Xcode target names (`CostBar-kx` and `PixelAPIWidget`) to avoid unnecessary project churn. If you fork the project, change only the signing identifiers below.

## Required Signing Values

In Xcode, update these Build Settings for both the main app target and the widget target:

- `DEVELOPMENT_TEAM`
- `PRODUCT_BUNDLE_IDENTIFIER`
- `RELAYBAR_APP_GROUP`

Recommended pattern:

```text
Main app bundle ID:    com.yourname.RelayBar
Widget bundle ID:      com.yourname.RelayBar.Widget
App Group identifier:  TEAMID.com.yourname.relaybar.widget
```

`RELAYBAR_APP_GROUP` is used by:

- `CostBar-kx.entitlements`
- `PixelAPIWidget/PixelAPIWidget.entitlements`
- `Info.plist`
- `PixelAPIWidget/Info.plist`
- `Shared/PixelDashboardSnapshot.swift`

The main app and widget must use the same App Group value or WidgetKit will not see the shared cache.

## XcodeGen

`project.yml` mirrors the checked-in Xcode project. If you regenerate the project with XcodeGen, update the same signing values there first.

## Secrets

Do not commit API keys or exported local caches. Credentials should only live in macOS Keychain. Widget shared cache files must not contain headers, cookies, bearer tokens, or raw credentials.
