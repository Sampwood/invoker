# Invoker

Invoker is a macOS menu bar app. The current version focuses on a compact calendar popover with month navigation, today highlighting, date selection, and a lightweight right-click menu.

## Requirements

- macOS 13 or newer
- Xcode with macOS SDK support
- GitHub Actions macOS runner for CI and release builds

## Project Structure

```text
Sources/
  App/                 App entry point and delegate
  Features/
    Calendar/          Calendar model, formatting, status icon, and popover UI
    InputSource/       Global input source lock
    Updates/           GitHub Releases update checker
  Shell/
    Popover/           Popover panel positioning
    StatusBar/         Status bar item and context menu
  Resources/           Info.plist
Tests/                 Unit tests
scripts/               Local development helpers
```

## Local Development

Open `Invoker.xcodeproj` in Xcode and run the `Invoker` scheme.

The app is configured as a menu bar utility through `LSUIElement = YES`, so it does not show a Dock icon or main window. Left-click the menu bar icon to open the calendar popover. Right-click it to open the app menu.

## Testing

Run unit tests with:

```bash
xcodebuild test \
  -project Invoker.xcodeproj \
  -scheme Invoker \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

GitHub Actions runs the same test command on pushes to `main` and on pull requests.

## Release

Create and push a version tag to publish a release:

```bash
git tag v1.0.0
git push origin v1.0.0
```

The release workflow builds the `Invoker` scheme in Release configuration, sets `MARKETING_VERSION` from the tag name, applies ad-hoc code signing, packages `Invoker.app` into a DMG with an `Applications` shortcut, and uploads it to a GitHub Release.

Current release DMGs contain an ad-hoc signed app and are not Apple notarized. After downloading, macOS may warn that the developer cannot be verified or may require manual approval in System Settings. For a fully trusted distribution flow, add Developer ID signing, hardened runtime, notarization with `notarytool`, and stapling before publishing.

## Update Checks

Invoker includes a manual update check in the right-click menu. It requests the latest release from:

```text
https://api.github.com/repos/Sampwood/invoker/releases/latest
```

The app compares the latest release tag, such as `v1.0.1`, with `CFBundleShortVersionString` from the app bundle. When a newer version is available, it prompts the user and opens the GitHub Release page. Invoker does not automatically download, install, or replace the local app.

For local builds, update `MARKETING_VERSION` in the Xcode project when you want the app's local version to match a release tag.
