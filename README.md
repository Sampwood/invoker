# Invoker

Invoker is a macOS menu bar app. It combines a compact calendar, selection screenshots, and a lightweight translation panel with OpenAI-compatible AI and DeepL providers.

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
    HotKey/            Global screenshot and selection-translation shortcuts
    InputSource/       Global input source lock
    Screenshot/        Interactive selection capture to the clipboard
    Translation/       Translation providers, secure settings, selection reading, and UI
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

## Translation

Choose `翻译...` from the right-click menu to open the translation panel for manual input. Select text in another application and press `Option + F` to read the current Accessibility selection, open the panel, and translate immediately. Invoker does not simulate `Command + C` or alter the clipboard while reading a selection.

Translation settings are available from `设置...` in the right-click menu:

- `AI` uses the OpenAI-compatible Responses API. Configure the provider's `base_url`, model, and optional API key; Invoker appends `/responses` while preserving a versioned custom base path. For example, the cc-switch configuration `base_url = "https://api.krill-ai.com/codex/v1"` maps to `https://api.krill-ai.com/codex/v1/responses`. A non-empty API key sends `Authorization: Bearer ...`, equivalent to `requires_openai_auth = true`; an empty key omits that header for local services. The default base URL is `https://api.openai.com/v1`.
- `DeepL` uses only the official DeepL API. Keys ending in `:fx` use the Free API host; other keys use the Pro API host.
- The default smart language pair is Simplified Chinese and English. When the detected source matches the preferred language, Invoker targets the secondary language; otherwise it targets the preferred language.

The selection shortcut requires macOS Accessibility permission. If permission or selected text is unavailable, Invoker opens the input panel without using a clipboard fallback. API keys are stored in macOS Keychain. Source text is sent only to the provider selected for the current request; Invoker does not keep translation history or cache network responses.

The product flow and provider boundaries are informed by [Easydict](https://github.com/tisfeng/Easydict). Invoker does not copy Easydict source code, prompts, artwork, or icons.

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
