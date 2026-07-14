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
    Updates/           Sparkle in-app updater
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

The release workflow builds the `Invoker` scheme in Release configuration, sets `MARKETING_VERSION` from the tag name, applies ad-hoc code signing, packages `Invoker.app` into a DMG with an `Applications` shortcut, signs the update archive and feed with Sparkle EdDSA, and uploads both the DMG and `appcast.xml` to a GitHub Release.

Current release DMGs contain an ad-hoc signed app and are not Apple notarized. The first Sparkle-enabled release is `v0.1.4`; existing users must download and install that bridge release manually and may need to approve it once in System Settings. Starting with `v0.1.5`, users who already have a Sparkle-enabled build should update in-app instead of downloading each DMG again. For a fully trusted first-install flow, add Developer ID signing, hardened runtime, notarization with `notarytool`, and stapling before publishing.

Before publishing the bridge release, generate a project-specific Sparkle Ed25519 key using the account name `com.sampwood.invoker`, keep the private key in the login Keychain and an encrypted backup, and configure the exported private key as the `SPARKLE_PRIVATE_KEY` GitHub Actions secret. Only the corresponding public key belongs in `Info.plist`; never commit or log the private key. The release workflow intentionally fails before publishing when the secret is missing.

## In-App Updates

Invoker uses Sparkle 2.9.4 and reads its signed update feed from:

```text
https://github.com/Sampwood/invoker/releases/latest/download/appcast.xml
```

Sparkle checks for updates in the background at an hourly interval, and the right-click menu keeps its manual `检查更新...` action. Updates require user confirmation. Sparkle verifies both the signed feed and the DMG before extraction, then replaces and relaunches the installed app. It does not fall back to opening a browser when verification or installation fails.

Copy Invoker to `/Applications` before running it; do not run it directly from the read-only DMG. Sparkle may request administrator authorization when `/Applications` is not writable. That authorization is distinct from Gatekeeper's `仍要打开` approval.

For local builds, update `MARKETING_VERSION` in the Xcode project when you want the app's local version to match a release tag.
