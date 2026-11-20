# UI test implementation and verification

## Production action supplement — 2026-11-16 (started 14:48)

Live-tested the existing developer PID 86203 without building/restarting it. Eight built-in commands plus two independent global shortcuts: **10 checks / 7 passed / 3 pending**. Passed Calendar, System Monitor, Settings, manual translation (both real AI and DeepL responses), Clipboard History, Check Updates, and global Shift+Command+V. Option+Space also passed from Chrome as supplementary existing coverage, not another counted item.

**C2/H1 blocked:** both the launcher selection-translation command and global Option+F reach the translation panel, but the running developer app explicitly reports missing Accessibility permission. Native test-tool AX permission does not grant the app itself permission. **C8 unexecuted:** Quit Invoker was previewed only, because executing it would violate the earlier explicit instruction to preserve the running development app; awaiting specific permission to close it. Original Liquid Glass remains **7/8 passed, 3.2 pending**; isolated infrastructure remains **4/4 verified**, not rerun this turn.

All 73 watched-file hashes and developer PID/start time match baseline; final app windows zero. Clipboard changeCount stayed 430 during history checks, no item copied/pasted/deleted. Real command usage statistics were naturally updated. No permissions/settings were changed, no update installed, no production code edited. Full evidence/report: `.build/UIRegression/20261116-production-actions/report.md`.

## Latest acceptance — 2026-11-16 14:34

**Isolated suite passed: 5 executed, 5 passed, 0 failed/skipped, exit 0.** Infrastructure checklist **4 total / 4 verified / 0 pending**: items 2 and 4 are now accepted. Liquid Glass checklist remains **8 total / 7 passed / 1 pending (3.2)** because production built-in actions and independent global shortcuts are outside this suite and remain unverified. The five test cases are coverage, not five additional checklist items. Original OpenSpec task files were not edited.

The user's screenshot identifies two relevant permission prompts: runner access to Documents, and testmanagerd enabling Sogou Pinyin. With explicit authorization, terminated only current-user testmanagerd PID 1194; XCTest recreated it as PID 71559. The immediate retry still failed 3 of 4 tests after keyboard synthesis brought System Settings foreground, so service restart alone did not solve the interruption. No system permission, input-source configuration or system dialog was changed.

The working input path keeps XCTest lifecycle/AX assertions/clicks/hover/screenshots and uses a small native CGEvent helper in the invoking terminal's existing AX/event-posting permission context. The helper checks the exact test bundle, per-run app path, PID, launch time, foreground state and key whitelist before delivery. Its safety self-check rejected a non-host process. The sandboxed runner writes requests in its own per-run container directory; runtime action receipts and all build/cache output remain under this run's `/private/tmp` directory. The helper is stopped when the script exits. No real application is launched by the action double.

Passed coverage: app-action receipt and exactly one usage record; stationary Row 04 hover then five Down keys reveal selected Row 09; actual numeric query input, result inclusion/exclusion and screenshot; long title/subtitle truncation with complete ⇧⌘V, click and Return execution via doubles, close/reopen reset; scan indicator with five complete recommendations, typed query while the controlled scan is held, and query/selection preserved on scan completion. Five exported screenshots were visually reviewed.

Development PID **86203**, start **2026-11-16 10:43:09 CST**, remains unchanged. All **73 watched-file hashes** match baseline; **7 runtime data files** match their archives. No host, runner, xcodebuild or native input helper remains. The final test log has no `UserNotificationCenter` / “警告” entries; this establishes no recurrence in this run, not permanent resolution of macOS permission flows.

Command: `./scripts/ui-test.sh`. Evidence and full Chinese report: `.build/UITests/Runs/20261116-143420-n1nzEg/report.md`; result bundle, summary, logs, screenshots, data and isolation checks are alongside it. Service reset baseline: `.build/UITests/ServiceReset-20261116-1423/`.

Remaining limits: the invoking terminal must already have native permissions; Chinese IME composition, production actions/global shortcuts and the separately deferred Chinese system-application search remain unverified. No production source or development Xcode project was modified this turn. Historical results below are superseded by this acceptance.

## Latest remaining-issue investigation — 2026-11-16 14:02–14:16

**Not accepted yet.** Infrastructure is now **2 verified / 2 pending (2, 4)**: item 4 is reopened because the current complete script failed again. Liquid Glass remains **7 passed / 1 pending (3.2)**. The previous reports below are historical.

Host-only tracing confirmed that System Settings became foreground after XCTest typing and the real launcher correctly dismissed on focus loss. LaunchServices logs attribute that activation to testmanagerd, at synthesis completion; its internal reason remains unknown. A per-key experiment also failed and was reverted. The hover test now injects its fixed initial query, while the smoke test retains actual typing. Added an application-execution double test with receipt and single usage-record assertions.

Another concrete trigger was recorded when the runner tried to read action receipts under the protected Documents folder: tccd logged a `kTCCServiceSystemPolicyDocumentsFolder` request and `display_prompt`. The script now places both runtime data and DerivedData in a unique `/private/tmp/invoker-ui-tests-<suffix>` directory and archives data after XCTest exits. This removes the runner's direct Documents receipt access; it does not establish that the entire system interruption is solved.

Final run `20261116-141406-ev1JtQ` built both targets, but still logged an unhandled “警告” Dialog from `com.apple.UserNotificationCenter`. Canceled: exit **73**, **0 passed**, **3 assertion failures and 1 cancellation**. The dialog body and actual visibility remain unverified. No attempt to access the tool-denied system app, grant permissions, or restart shared services was made. A shared-testmanagerd reset is a possible next diagnostic, requiring authorization beyond managing only test instances; it is not a proven fix.

Development PID **86203**, start **10:43:09 CST**, and **73 watched-file hashes** are unchanged. No test processes remain. Four runtime data files were archived with matching hashes. Shell syntax/diff checks passed. Full report and all evidence: `.build/UITests/Runs/20261116-141406-ev1JtQ/report.md`.

## Latest reconfirmation — 2026-11-16 13:55

At the user's request, ran the unchanged `./scripts/ui-test.sh` once. The prior interruption was **not reproduced in this run's log**: zero `UserNotificationCenter` and zero `"警告" Dialog` entries. This does not establish permanent resolution or the visibility/body of the earlier dialog.

**3 tests executed, 2 passed, 1 failed; exit 65.** The minimal launch/search/assert/screenshot/terminate flow passed, including unchanged development-instance assertions. The long-text/keycap and click/Return command-double flow also passed; its screenshot visually confirms both text lines truncate while `⇧⌘V` remains fully visible. The hover test failed at line 65 while waiting for Fixture Row 04, before performing any hover. Its failure snapshot contains only the host entry window; the launcher has disappeared. The cause remains unknown and is not attributed to the earlier warning.

Infrastructure is now **3 verified / 1 pending (2)**: item 4 is verified by the complete smoke flow; item 2 still needs the application-launch double execution branch, although fixed data and command doubles passed. Liquid Glass is now **7 passed / 1 pending (3.2)**: item 2.1 combines prior live hover/selection checks with this run's long-text screenshot. Production actions, independent shortcuts and scanning-time input remain outside the completed scope.

Development PID **86203**, start **10:43:09 CST**, remains unchanged; all **73 files** enumerated under watched paths this turn have matching before/after hashes. No test processes remain. No source/test changes or permission changes were made this turn. Full report: `.build/UITests/Runs/20261116-135541-putqQ3/report.md`; logs, xcresult, screenshots, action receipts and isolation checks are in the same directory.

## Latest observed retry — 2026-11-16 13:38–13:48

The user asked to watch another run. The final invocation reproduced the system interruption at approximately **13:46:29 CST**: XCTest logged a **“警告” Dialog** from `com.apple.UserNotificationCenter`. Its body remains unknown; Computer Use previously denied this app, and no alternate inspection or permission change was attempted. Canceled only this test session. Exit **73**, **0 passed**, one timeout and one cancellation in the result summary; the third test did not run. No further retry under the same blocker.

Earlier attempts in this turn supplied concrete test fixes: numeric fixture keywords avoid the active Chinese IME converting Latin input; the launcher is an AX Dialog; screenshot PNG writes from the sandboxed runner failed, so tests now retain XCTest attachments and use the script's existing export. The Calendar query/result assertions and an actual screenshot were reached before that write failure, but this is only partial smoke-flow evidence. The final run also checked foreground state and the literal query before the target panel later disappeared. No action receipt or full passing test is claimed.

Development PID **86203**, start **10:43:09 CST**, and all **70 watched files** remained unchanged. No test processes remained after cancellation. Checklists remain: infrastructure **2 verified / 2 pending**; Liquid Glass **6 passed / 2 pending (2.1, 3.2)**. Current report: `.build/UITests/Runs/20261116-134409-JHGasO/report.md`; blocker excerpt, result summary and isolation checks are alongside it. Partial actual search screenshot: `.build/UITests/Runs/20261116-134046-KptyW6/Attachments/0B3666C2-D3FB-40BF-930F-96B2A75EC702.png`.

The records below are historical and do not supersede this outcome.

## Latest retry after enabling UI Automation — 2026-11-16 13:02–13:08

Automation-mode initialization now succeeds. The first actual run exposed a test-only UserDefaults adapter initialization failure; fixed by using a convenience initializer that retains Foundation initializer inheritance. Its isolated file read/write self-check passed, and the next run loaded the host's Open Launcher window.

The corrected run was then blocked by a system “警告” dialog from `com.apple.UserNotificationCenter`. XCTest's interruption monitors did not handle it; the launcher search field did not appear. Computer Use explicitly denied access to that system app, and no alternate access was attempted. Canceled the isolated session rather than repeat under unchanged conditions. Final exit 73 (cancellation/result-finalization warning), 0 tests passed, one canceled test in the result summary. All 70 watched files and development PID 86203/start 10:43:09 remained unchanged; no test processes remained.

Checklists remain unchanged: infrastructure 2 verified / 2 pending; Liquid Glass 6 passed / 2 pending. Latest evidence: `.build/UITests/Runs/20261116-130628-V5QQ1d/report.md`. Requires the user to identify/handle the system warning before another run. No successful launcher screenshot or action receipt was produced.

## Latest run — 2026-11-16

The user explicitly authorized `./scripts/ui-test.sh`. Executed once: the current host and all three UI test methods compiled and signed, but **0 methods ran**, exit **65**, with the same automation-mode initialization timeout. No runtime pass is claimed; the infrastructure checklist remains **2 verified / 2 pending**, and the separate Liquid Glass checklist remains **6 passed / 2 pending (2.1, 3.2)**.

New system-log evidence identifies the immediate gate: `Writer daemon requires authentication to enable automation mode.`, followed by LocalAuthentication for `Enable UI Automation`. The user must complete this system authentication before another execution. No permissions were changed and no automatic retry occurred.

Development PID **86203**, launched **2026-11-16 10:43:09 CST**, was unchanged before/after. All 70 watched-file hashes matched. No test host/runner remained. No test data directory, action receipt, or screenshot was created; exported attachments were empty.

Latest report and evidence: `.build/UITests/Runs/20261116-111056-YKqs5B/report.md`. The earlier verification below is preserved as history.

Date of earlier run: 2026-11-14, Asia/Shanghai.

## Overall status

Four tracked items: **2 verified, 2 pending**. The test host and UI runner compiled successfully. The real UI run was blocked before the test method began; it is not a passing smoke test.

Run command from the repository root:

```bash
./scripts/ui-test.sh
```

## Pending

| ID | Item | Current evidence and remaining acceptance |
| --- | --- | --- |
| 4 | Minimal UI flow and runtime isolation | The XCUITest runner timed out enabling automation mode. The method `testLaunchSearchScreenshotAndTerminate` did not execute. Need a successful launch, launcher opening, typed query, result assertions, actual screenshot, test-host termination and unchanged development-process assertion. |
| 2 | Fixed fixtures and execution doubles | The host compiled using the existing model/store/launcher injection interfaces. Its usage adapter writes only under the supplied run directory; commands and application launches record a test receipt. Runtime behavior and absence of unintended side effects remain unverified because item 4 never began. The smoke test itself does not execute either action double. |

The initialization error does not identify whether the underlying cause is a permission, desktop-session or XCTest service problem. No system settings or permissions were changed. After this environment error, the UI run was not retried.

## Verified

| ID | Item | Evidence and verification limits |
| --- | --- | --- |
| 1 | Isolated project, targets and build products | Both targets compiled and were ad-hoc signed. Built Info.plists identify `com.sampwood.invoker.uitesthost` / `InvokerUITestHost` and `com.sampwood.invoker.uitests.xctrunner` / `InvokerUITests-Runner`. Build output is under `.build/UITests/DerivedData`. The standalone project references the seven existing launcher files and excludes production startup, global hotkeys, monitoring and updates. All 70 files under the development watcher's existing paths matched their pre-run hashes. This verifies the infrastructure and build, not runtime UI or data behavior. |
| 3 | One-command execution and failure evidence | `scripts/ui-test.sh` ran, retained build/test logs and `.xcresult`, preserved Xcode's exit code 65 and exported an empty attachment manifest. Shell syntax and project plist checks passed. There is no retry flag, Finder launch, development watcher invocation or process-killing command. Successful screenshot capture/export still belongs to pending item 4. |

## Actual execution

1. Initial invocation was rejected before compilation because this Xcode requires `-test-iterations` to exceed 1. Removed the flag; the default single run is used.
2. Executed the corrected script once. Both targets compiled and code signed. At 20:07:52 the runner began initialization; at 20:08:52 it reported:

   ```text
   Failed to initialize for UI testing:
   Timed out while enabling automation mode.
   ```

3. Xcode completed with `TEST FAILED`, exit code **65**. The `.xcresult` summary records **0 passed** and **1 runner initialization error**; that entry is not an executed application test or a failed UI assertion.
4. Stopped UI execution attempts. The empty exported attachment manifest and missing direct PNG confirm that no launcher screenshot was produced.
5. A read-only process snapshot after the run found the development app at PID **8952**, with launch time **20:05:12**, earlier than the test invocation. No `InvokerUITestHost` or `InvokerUITests-Runner` remained. The runtime before/after assertion in the UI test was not reached.

## Evidence

Primary run directory:

`/Users/Sampwood/Documents/code/self/invoker/.build/UITests/Runs/20261114-200742-9Tyoct`

- `xcodebuild.log`
- `exit-code.txt`
- `Results.xcresult`
- `test-summary.json`
- `Attachments/manifest.json` — empty.
- `attachments-export.log`
- `processes-after.txt`
- `watched-files-check.json`
- `verification-checks.json` — project/scheme validity, bundle IDs, unchanged watched files, exit status and missing screenshot.

The parameter-rejected invocation is retained separately at:

`/Users/Sampwood/Documents/code/self/invoker/.build/UITests/Runs/20261114-200718-fS10yk`

Expected screenshot after a future successful run:

`<printed run directory>/launcher-search-calendar.png`

No screenshot, test data initialization or action receipt is claimed for this blocked run.

## Remaining scope and risks

- A successful run in the logged-in desktop session is required before accepting the smoke test. If macOS presents an authorization request, the user must handle that system flow.
- The test uses the real launcher code in a small isolated host; it does not exercise the production status-bar entry or full application startup.
- Light/dark appearance, accessibility variants, keyboard scrolling, clear/search reset and all production commands are outside this first smoke flow.
- No global shortcuts are registered. No real application execution is requested.
- XCTest may initialize its services before applying the per-test 90-second timeout. The current failure exited without manual process cleanup; abrupt runner termination in a future run is not yet verified.
