# Invoker

Invoker is a macOS menu bar app. It combines a compact calendar, clipboard history, and a lightweight translation panel with OpenAI-compatible AI and DeepL providers.

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
    HotKey/            Global selection-translation and clipboard-history shortcuts
    InputSource/       Global input source lock
    Translation/       Translation providers, settings, selection reading, and UI
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

Invoker does not provide an in-app screenshot action. Use the native macOS shortcuts `Shift + Command + 4` for a selection or `Shift + Command + 5` for the system screenshot toolbar.

## Translation

Choose `翻译...` from the right-click menu to open the translation panel for manual input. Select text in another application and press `Option + F` to read the current Accessibility selection, open the panel, and translate immediately. Invoker does not simulate `Command + C` or alter the clipboard while reading a selection.

Translation settings are available from `设置...` in the right-click menu:

- `AI` uses the OpenAI-compatible Responses API. By default, every request reads the current Codex provider from `~/.cc-switch/cc-switch.db`, so switching providers in cc-switch takes effect on the next translation without restarting Invoker. Invoker reads only the current provider's `model`, `base_url`, `wire_api`, `requires_openai_auth`, and `OPENAI_API_KEY`; it never reads OAuth access or refresh tokens and does not copy the cc-switch API key into Invoker's config. Invoker appends `/responses` while preserving a versioned custom base path.
- The AI settings source can be switched between `CC Switch` and `Manual`. When `CC Switch` is selected but cannot provide a valid Responses API configuration, Invoker uses the manual Base URL, model, and API key as a per-request fallback and shows a warning.
- `DeepL` uses only the official DeepL API. Keys ending in `:fx` use the Free API host; other keys use the Pro API host.
- The default smart language pair is Simplified Chinese and English. When the detected source matches the preferred language, Invoker targets the secondary language; otherwise it targets the preferred language.

Invoker's manual AI fallback key and DeepL key are stored as plaintext in `~/.invoker/config.json`:

```json
{
  "ai_api_key": "",
  "deepl_auth_key": ""
}
```

Invoker creates `~/.invoker` with mode `0700` and `config.json` with mode `0600`. These permissions restrict other local accounts, but they do not encrypt the secrets or protect them from software running as your account. On the first launch after upgrading, Invoker copies its legacy translation keys from macOS Keychain into this file and removes the old Keychain entries only after the file is valid.

The selection shortcut requires macOS Accessibility permission. If permission or selected text is unavailable, Invoker opens the input panel without using a clipboard fallback. Source text is sent only to the provider selected for the current request; Invoker does not keep translation history or cache network responses.

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

Publish releases from the GitHub Releases page. Choose a new tag such as `v1.0.0`, target the commit to release, select **Set as a pre-release**, and publish it. Do not publish it as a stable release initially: the Sparkle feed uses GitHub's `latest` release, which must not point at a release before its signed assets are ready.

The `published` release event starts the release workflow. It checks out the release tag, builds the `Invoker` scheme in Release configuration, sets `MARKETING_VERSION` from the tag name, applies ad-hoc code signing, packages `Invoker.app` into a DMG with an `Applications` shortcut, and signs the update archive and feed with Sparkle EdDSA. After all validation succeeds, the workflow uploads the DMG and `appcast.xml` to that same pre-release and promotes it to the stable latest release. If the build or validation fails, the release remains a pre-release and the previous stable Sparkle feed stays available.

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
