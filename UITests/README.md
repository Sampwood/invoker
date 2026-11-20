# Invoker UI tests

Run from the repository root:

```bash
./scripts/ui-test.sh
```

Requires Xcode 26 and an unlocked, logged-in macOS 26 desktop. Run from a terminal in that desktop session with existing Accessibility and event-posting permission for native input, plus XCTest UI automation permission. The helper checks existing permission without requesting it; a missing permission stops the run before building. If macOS requires a new permission, the user must handle that system flow. The script does not grant permissions, retry failures, restart testmanagerd, or change system settings.

## Isolation

The standalone `InvokerUITests.xcodeproj` contains:

- `InvokerUITestHost`: bundle ID `com.sampwood.invoker.uitesthost`, executable `InvokerUITestHost`.
- `InvokerUITests`: XCTest / XCUITest target, bundle ID `com.sampwood.invoker.uitests`; Xcode creates the separate `InvokerUITests-Runner` process.

It directly compiles the seven existing launcher source files. It does not compile the production `AppDelegate`, status bar, updater, input source lock, clipboard monitor or global hotkey controller. It has no external package dependencies.

The host injects fixed commands, a fixed application list, a file-backed usage-store test double and a recording application-launching test double through the existing interfaces. Actions write only a receipt under the test data directory. They do not launch real applications or execute production commands. The hover test injects its initial query (`90004`) through `INVOKER_UI_TEST_QUERY`; the smoke and scanning tests separately verify real keyboard input.

XCTest manages the test lifecycle, clicks, hover, accessibility assertions and screenshot attachments. `native-input.swift` sends the fixed query/navigation key events through CGEvent because XCTest keyboard synthesis triggered the Sogou input-source consent flow and switched focus to System Settings in this environment. The helper runs in the invoking terminal's existing permission context; the sandboxed runner itself lacks native event-posting permission. Every key requires the test host's exact bundle ID, this run's app path, PID, launch time and foreground state. Only a small key whitelist is accepted. No clipboard or input-source settings are changed. A startup self-check verifies rejection of a non-host process.

The production sources and `Invoker.xcodeproj` are not edited. This matters because `scripts/dev-run.sh` watches those paths and restarts the development app when they change. The UI test script does not run that watcher, use Finder, call `pkill`, or terminate any `Invoker` process. XCTest launches and terminates only its `com.sampwood.invoker.uitesthost` application.

## Minimal flow

1. Capture the existing development processes' PIDs and launch times.
2. Launch `InvokerUITestHost` through `XCUIApplication`.
3. Click the test host's **Open Launcher** button, which calls the real `LauncherPanelController.show()`.
4. Wait for the fixed scan to finish; send the physical digit keys for `90001` to the foreground test host's real search field. Numeric keywords remain literal with the current Chinese input method, so tests do not change the user's input source.
5. Assert exactly one matching **Fixture Calendar** result, absence of the other fixtures and preservation of the query.
6. Retain a screenshot of the launcher dialog as an XCTest attachment; the script exports it as a PNG after the run. The sandboxed runner does not write screenshots directly into the run directory.
7. Terminate the test host, wait for `.notRunning`, and assert that the development processes' PIDs and launch times are unchanged.

The five tests cover the minimal flow; stationary hover followed by keyboard scrolling; long text with a full shortcut keycap and command execution by click/Return; application execution through the recording double with a usage-count assertion; and scanning-time input. The scanning fixture waits for a test-owned release file so assertions and screenshots happen while scanning, then checks that completion preserves the typed query and selection.

The requested test timeout is 90 seconds; Xcode may round it up to two minutes. There is no automatic retry. Xcode may still take additional time to initialize or shut down its test services.

## Evidence

Each run creates `/private/tmp/invoker-ui-tests-<suffix>/` for its `DerivedData` build directory, native helper's `SwiftModuleCache`, and `Data/<test UUID>/` runtime data, independently of the development build and protected Documents folder. The runner reads receipts there. It writes input requests and the scan-release marker only to its own container at `~/Library/Containers/com.sampwood.invoker.uitests.xctrunner/Data/tmp/invoker-ui-tests-<suffix>/`; the native helper reads requests there. Once XCTest exits, the shell script copies `Data/` and the input files into the evidence directory. Temporary directories are retained for diagnosis; their exact locations are recorded in `runtime-directory.txt` and `native-input-directory.txt`. The script terminates only its own input helper on exit.

Each invocation prints a unique `.build/UITests/Runs/<timestamp>-<suffix>/` directory containing:

- `xcodebuild.log`: complete build and test output.
- `exit-code.txt`: the original `xcodebuild` exit code.
- `runtime-directory.txt`: the independent build and runtime-data directory.
- `native-input.log`: permission/initialization diagnostics, safety check and targeted key delivery records.
- `native-input-directory.txt`, `Input/`: the runner's per-run input directory and archived request/response/scan marker files.
- `Results.xcresult`: Xcode's result bundle.
- `Attachments/`: exported XCTest attachments and a manifest mapping `launcher-search-calendar`, `launcher-hover-keyboard-regression`, `launcher-long-text-keycap`, `launcher-scanning-five-rows` and `launcher-scanning-typed-query` to their PNG filenames, when those capture points are reached and export succeeds.
- `attachments-export.log`: export diagnostics.
- `Data/<test UUID>/com.sampwood.invoker.uitesthost/launcher-usage.json`: isolated usage data.
- `Data/<test UUID>/com.sampwood.invoker.uitesthost/last-action.txt`: created only if a test executes a fixture action.

Do not treat a successful build as a successful UI test. A blocked run may contain logs and an `.xcresult` without a launcher screenshot. Production appearance, full command routing, real application launching and global shortcuts are outside this isolated suite.
