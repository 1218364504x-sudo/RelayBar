# RelayBar

RelayBar is a native macOS menu bar app with a floating window and WidgetKit desktop widgets for monitoring API relay provider balances and usage.

The user-facing metrics are:

- 余额
- 今日消费
- 今日 Token
- 累计 Token

The original Xcode target and scheme names are still `CostBar-kx` to keep the project history stable.

## Features

- Menu bar status and detail popover
- Multiple provider profiles with independent credentials
- New API / One API / Sub2API-style balance and usage compatibility
- Optional CC Switch current-provider following
- Optional floating balance window
- WidgetKit widgets in Small, Medium, and Large sizes
- Sanitized App Group cache shared from the main app to the widget
- macOS Keychain storage for credentials

## Architecture

```text
Main App
  ├─ reads credentials from Keychain
  ├─ refreshes selected provider data
  ├─ writes sanitized PixelDashboardSnapshot to App Group
  └─ reloads WidgetKit timelines

Widget Extension
  └─ reads only the App Group snapshot cache
```

Important files:

- `Shared/PixelDashboardSnapshot.swift`: shared snapshot model and App Group cache store
- `ViewModels/DashboardViewModel.swift`: refresh, profile, CC Switch, and widget publishing orchestration
- `Services/UsageServiceFactory.swift`: Pixel/New API/Sub2API-compatible dashboard fetching
- `Services/CCSwitchIntegrationService.swift`: optional CC Switch local database integration
- `PixelAPIWidget/PixelAPIWidget.swift`: WidgetKit UI

## Security Model

- API keys are saved only in macOS Keychain.
- API keys are not written to UserDefaults, JSON cache, plist files, README examples, or logs.
- The widget does not read Keychain.
- The widget does not make network requests.
- The widget does not read CC Switch.
- The widget reads only the sanitized App Group cache written by the main app.
- App Group cache files must never include `Authorization`, `Bearer`, `Cookie`, or raw credentials.

## Requirements

- macOS 14 or newer
- Xcode 16 or newer
- Apple development team for running the WidgetKit extension with App Groups

## Open Source Setup

Before building your fork, update signing values for both targets:

- `DEVELOPMENT_TEAM`
- `PRODUCT_BUNDLE_IDENTIFIER`
- `RELAYBAR_APP_GROUP`

Read [OPEN_SOURCE_SETUP.md](OPEN_SOURCE_SETUP.md) for the exact places these values are used.

## Run

Open `CostBar-kx.xcodeproj`, select the `CostBar-kx` scheme, and run.

Command-line debug build:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project CostBar-kx.xcodeproj \
  -scheme CostBar-kx \
  -configuration Debug \
  -derivedDataPath /tmp/relaybar-build \
  build
```

## Configure A Provider

1. Open RelayBar.
2. Open Settings from the menu bar popover.
3. Add or edit a provider profile.
4. Enter the provider credential.
5. Save and test the connection.

Use Clear Credential to remove a saved credential from Keychain.

## Add The macOS Widget

1. Right-click the desktop.
2. Choose Edit Widgets.
3. Search for RelayBar.
4. Add Small, Medium, or Large.
5. Open the main app and refresh once if the widget has no cache yet.

## CC Switch Integration

RelayBar can optionally follow the current CC Switch provider.

Modes:

- Read current status only
- Read current status and import the current provider key into RelayBar Keychain

CC Switch is read only by the main app. The widget never reads CC Switch directly.

## Pre-Commit Checks

Run these before publishing:

```bash
rg -n "sk-|Authorization|Bearer|Cookie|api-key" .
rg -n "DEVELOPMENT_TEAM|PRODUCT_BUNDLE_IDENTIFIER|RELAYBAR_APP_GROUP|App Group" README.md OPEN_SOURCE_SETUP.md project.yml CostBar-kx.xcodeproj/project.pbxproj
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CostBar-kx.xcodeproj -scheme CostBar-kx -configuration Debug build
```

Expected credential matches should be request-header implementation code, placeholders, or documentation warnings only.

## License

MIT. See [LICENSE](LICENSE).
