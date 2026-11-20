# Launcher Liquid Glass — Design QA

## Latest verification — 2026-11-14

The existing application was successfully attached after the updated desktop regression skill sent the project's confirmed Option+Space shortcut to the verified zero-window instance. PID 8952 and launch time 20:05:12 remained unchanged through multiple observations. The report below dated 2026-11-13 is historical and no longer describes current connection availability.

The original eight acceptance items are now **2 verified, 6 pending**: 1.1 retains its executed capacity test evidence, and 1.3 has real single-screen geometry and shadow evidence. Light appearance, two separate surfaces, real background blur, keyboard input, filtering, clearing, arrow navigation, manual scrolling, Esc and reopening have partial runtime evidence. Full appearance/accessibility and behavior matrices remain incomplete.

**Confirmed defect:** hovering over a lower row in a long result list triggers repeated scrolling and changes the selected target. A fix and regression checks are staged in `.build/UIRegression/20261114-hover-fix/`; they have not been applied to watched production source paths. The existing development watcher rebuilds and relaunches the app after source edits, conflicting with the current no-build/no-restart restriction.

- Full runtime report and evidence: `.build/UIRegression/20261114-existing-instance/report.md`.
- Real composited glass screenshot: `.build/UIRegression/20261114-existing-instance/12-composited-panel.png`.
- Controlled hover reproduction: `14-hover-repro-before.png`, `15-hover-repro-after.png` and corresponding AX logs in that directory.
- The final independent PID check was blocked by automatic approval review timeouts. No update buttons were operated and no application build, launch, restart or termination was initiated.
- Separate XCUITest infrastructure remains unverified at runtime; native AX access does not establish that XCTest automation mode now works.

Current final result: **not accepted — hover defect and incomplete coverage**.

## Historical verification — 2026-11-13

- Date: 2026-11-13.
- Change: `launcher-liquid-glass`.
- Source visual truth: `/Users/Sampwood/Documents/code/self/invoker/openspec/changes/launcher-liquid-glass/assets/launcher-liquid-glass-reference.png` (1544 × 1018 px, opened).
- Implementation target: the existing running Debug application at `/Users/Sampwood/Documents/code/self/invoker/.build/DerivedData/Build/Products/Debug/Invoker.app`.
- Implementation screenshot: unavailable; the native desktop tool timed out when selecting Invoker by full path and by application name.
- Intended viewport: 720 × 470 pt host window, including 20 pt padding around the 680 × 430 pt visible content. Actual rendered viewport was not observed.
- Intended state: empty query with five real recommendations, followed by search, scanning and no-result states. No actual launcher state was captured.

## Findings and evidence

Visual verification is blocked by the application connection timeout. Finder accessibility and screenshots were accessible, but they are not evidence of the launcher rendering. The user's running application is not considered stopped or faulty based on that tool failure.

Full-view comparison: not performed because no implementation screenshot was obtained. No combined reference/implementation comparison exists.

Focused comparison: not performed for the same reason. Search capsule edges, selected row, application icon, text truncation and shortcut keycaps still need close inspection.

| Required fidelity surface | Result |
| --- | --- |
| Fonts and typography | Unverified: actual font rendering, hierarchy, truncation and legibility were not captured. |
| Spacing and layout rhythm | The capacity XCTest passed; actual surface separation, alignment, centering, shadows and scrolling remain unverified. |
| Colors and visual tokens | Unverified in light/dark appearance, dense backgrounds and accessibility settings. |
| Image quality and asset fidelity | Unverified: no runtime application icon or material rendering was observed. |
| App-specific copy and content | Existing source copy is retained; runtime labels, scanning and empty states were not observed. |

No visual severity finding or pass is asserted without rendered evidence.

## Automated regression evidence

`InvokerTests/LauncherTests`: **8 passed**, 0 failed; `xcodebuild test` exited with code 0 and printed `TEST SUCCEEDED`.

- Aliases, selection and exclusion of paths from search.
- Successful execution recording and command dispatch order.
- Five recommendations plus scanning status fit within the result height.
- Recent-use ties and stable cold-start ranking.
- Recommendation limits and frequency before match quality.
- Refresh keeps cached results, current query and valid selection.
- Scanner boundary, symbolic-link and naming rules.
- Usage-window persistence and corrupt-data fallback.

Result bundle: `/tmp/InvokerLauncherRegression-Verified-20261113.xcresult`.

Execution log: `/tmp/InvokerLauncherRegression-Verified-20261113.log`.

These tests do not verify native window rendering or real keyboard/mouse interactions.

## Comparison history

1. Opened the selected reference image.
2. Native desktop connection to the Debug application timed out. No launcher screenshot, visual comparison or subsequent visual fix occurred.
3. Stopped attempts to reactivate the application after the user reiterated that it was already running.

## Remaining acceptance checklist

- Capture the existing running launcher without starting another instance, then compare it with the reference in one combined input.
- Inspect surface separation, row alignment, icons, keycaps, selection outline and shadows.
- Verify light/dark appearance, a dense background and accessibility variants.
- Verify real focus, clearing, arrow navigation, scrolling, safe execution, global shortcuts and dismissal behavior.

final result: blocked
