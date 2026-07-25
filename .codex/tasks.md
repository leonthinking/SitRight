# SitRight Agent Task Board

This is a lightweight coordination board for Codex and other coding agents.

Use it for multi-step work, deferred follow-ups, and handoffs. Do not use it as a substitute for Git history or issue tracking when the user provides another system.

## Task Template

```markdown
### TASK-YYYYMMDD-short-name

- Status: Backlog | Ready | In Progress | Done
- Goal:
- Impacted areas:
- Verification:
- Handoff notes:
```

## Backlog

No tracked tasks yet.

## Ready

No tracked tasks yet.

## In Progress

### TASK-20260723-verified-dmg-packaging

- Status: Done
- Goal: Adopt the reusable parts of CapCap's draggable-DMG workflow while preserving SitRight's stricter Widget/App Group signing requirements.
- Impacted areas: DMG packaging script, packaging regression contract, README, and packaged artifact verification.
- Verification: `bash -n Scripts/build_app.sh`, `bash -n Scripts/package_dmg.sh`, `swift test --disable-sandbox` (154/154), `./Scripts/build_app.sh`, `OPEN_DMG_ON_SUCCESS=0 ./Scripts/package_dmg.sh`, and `git diff --check` passed. The generated arm64 HFS+ UDZO image passed SHA-256 verification, `hdiutil verify`, read-only mounting, `Applications` link and content checks, strict App/Widget signature verification, TeamIdentifier `973KFG9CL9`, exact App Group validation, version/architecture consistency, and absence of `get-task-allow`. Failure injection preserved the previous App, DMG, and checksum. Two independent adversarial reviews completed with every confirmed P0-P2 finding repaired and covered.
- Handoff notes: Do not copy CapCap's self-signed/ad-hoc fallback into SitRight; both the main App and Widget require TeamIdentifier `973KFG9CL9` for runtime App Group access. Script output is Apple Development signed and internal-test only; public distribution still requires Developer ID Application signing, Hardened Runtime, a trusted timestamp, notarization, stapling, and quarantine/first-launch verification. A SIGKILL during the narrow final rename window of a standalone local build can leave the regenerable `build/SitRight.app` in its hidden same-volume staging directory; the package path, installed App, and DMG publication use persistent recoverable transactions.

### TASK-20260718-apple-inspired-activity-reminder

- Status: Done
- Goal: Redesign SitRight around a rolling Apple-inspired 50/1 activity cadence with a verified 60-second guide, independent reminder-opportunity timing, actionable notifications, and an adjustable daily activity goal.
- Impacted areas: Reminder state machine and runtime persistence, notification actions, activity-history schema and metrics, Today/settings/popup UI, Widget snapshots and presentation, accessibility, and migration/regression coverage.
- Verification: `swift test` passed 119/119; `./Scripts/build_app.sh` completed with `** BUILD SUCCEEDED **` and produced `build/SitRight.app`; `git diff --check` passed; architecture and product adversarial reviews completed with confirmed findings repaired and regression coverage added.
- Handoff notes: Preserve existing saved interval and delivery preferences; apply 50 minutes, notifications on, sound off, and strong popup off only to fresh installs. Do not edit the generated Xcode project. Packaged notification authorization/action, VoiceOver, lock/sleep, and widget visual checks remain manual follow-up because they require running the signed app and changing system state.

## Done

### TASK-20260725-merge-general-schedule-settings

- Status: Done
- Goal: Merge the visible General and Schedule settings panes into one native scrolling General pane while preserving old schedule selections and contextual entry points.
- Impacted areas: Settings pane/section routing compatibility, Settings content organization, menu-to-Settings navigation, keyboard and VoiceOver focus, and focused presentation tests.
- Verification: Settings/presentation tests passed 34/34; `swift test --disable-sandbox --skip PackagingContractTests` passed 144/144; the final full 151-test run reached only the four known dirty-DMG contract assertion failures in `PackagingContractTests` at lines 165, 167, 169, and 181; `./Scripts/build_app.sh` completed with `** BUILD SUCCEEDED **`; `git diff --check` passed. Two independent adversarial reviews completed, with the confirmed contextual-section navigation and route-test findings fixed and re-reviewed with no remaining P0-P3.
- Handoff notes: The visible Settings tabs are General and Notifications at the existing 460×380 size. Legacy `.schedule` values migrate to General and request one-time scrolling/focus to Work Schedule; the menu's contextual schedule entry uses the same route. Preserve immediate persistence, `AppSettings` encoding, ReminderEngine behavior, and all unrelated Widget, DMG, README, and Marketing changes. The structurally signed build was not installed or launched because it has no `TeamIdentifier`; final `⌘,`, VoiceOver, Full Keyboard Access, and visual scrolling checks require a correctly signed artifact.

### TASK-20260725-guide-window-lifecycle

- Status: Done
- Goal: Close the status-item popover before an activity guide appears, make the guide panel layout controlled and accessible, and preserve compatible menu/settings layouts.
- Impacted areas: Status popover phase/lifecycle coordination, deferred guide presentation, reminder panel sizing and actions, adaptive menu controls, legacy schedule picker values, and focused UI-policy tests.
- Verification: Lifecycle/presentation/engine tests passed 56/56; `swift test --disable-sandbox --skip PackagingContractTests` passed 141/141; the full 148-test run reached only the four known dirty-DMG contract assertion failures in `PackagingContractTests` at lines 165, 167, 169, and 181; `./Scripts/build_app.sh` completed with `** BUILD SUCCEEDED **`; `git diff --check` passed. Two independent adversarial reviews completed, with the confirmed asynchronous-close, closing-lifecycle, and measurement-contract findings fixed, covered, and re-reviewed with no remaining P0-P3 findings.
- Handoff notes: Preserve the single `AppContainer`, existing ReminderEngine semantics, disabled automatic hosting preferred sizing, hidden-popover refresh gate, and all unrelated Widget, DMG, README, and Marketing changes. The structurally signed build was not installed or launched because it has no `TeamIdentifier`; final focus, notification-entry, VoiceOver, Full Keyboard Access, appearance, and CPU/RSS smoke checks require a correctly signed artifact.

### TASK-20260725-menu-ui-regressions

- Status: Done
- Goal: Restore the standard Settings window content and keep the activity timer ring fully inside its 168 pt drawing bounds.
- Impacted areas: SwiftUI App/AppDelegate container lifetime, Settings scene environment injection, timer-ring geometry, and focused presentation regression coverage.
- Verification: `MenuPanelPresentationTests` passed 13/13; `swift test --disable-sandbox --skip PackagingContractTests` passed 132/132; the final full 139-test run reached only the four known dirty-DMG contract assertion failures in `PackagingContractTests`; `./Scripts/build_app.sh` completed with `BUILD SUCCEEDED`; `git diff --check` passed; two independent adversarial reviews completed, with confirmed stroke clipping, near-full cap overlap/plateau, Dynamic Type crowding, and guiding-plus-due progress issues fixed and re-reviewed.
- Handoff notes: Preserve the single `AppContainer`, the controlled popover sizing path, and all unrelated Widget, packaging, README, and Marketing worktree changes. The structurally signed build was not installed or launched because it has no `TeamIdentifier`; perform the final Settings single-instance/Command-comma and Retina visual smoke checks on a correctly signed artifact.

### TASK-20260725-menu-ui-settings

- Status: Done
- Goal: Simplify the menu-bar popover around today’s status and immediate actions, move low-frequency preferences into the standard macOS Settings window, and preserve the existing popover performance protections.
- Impacted areas: App lifecycle and Settings scene, menu popover presentation/actions, controlled popover sizing, accessibility semantics, and focused UI-state regression tests.
- Verification: `swift test --disable-sandbox --skip PackagingContractTests` passed 127/127; the full 134-test run reached only the four pre-existing dirty DMG contract assertions in `PackagingContractTests`; `./Scripts/build_app.sh` completed with `** BUILD SUCCEEDED **`; `git diff --check` passed; two independent adversarial reviews completed, with the confirmed phase-label/accessibility and measurement-gating findings fixed and rechecked.
- Handoff notes: Preserve the single `AppContainer`, disabled automatic preferred sizing, hidden-popover refresh gate, and layout-signature-only measurement path. A read-only layout probe confirmed 370 pt action copy and 900/400/250 pt height behavior. Packaged Settings single-instance/`⌘,`, Full Keyboard Access/VoiceOver focus transitions, appearance variants, and open/closed 10-minute CPU/RSS sampling remain manual because the local Computer Use runtime could not inspect the LSUIElement process and System Events access was unavailable. The local build is structurally signed without TeamIdentifier, so it does not validate App Group/Widget runtime sharing.

### TASK-20260723-widget-app-group-signing

- Status: Done
- Goal: Restore Widget access to the existing App Group history and prevent an ad-hoc build without the required TeamIdentifier from replacing the working installation.
- Impacted areas: Build/install signing validation, packaged App/Widget registration, README, project context, and live Widget shared-data verification.
- Verification: `swift test` passed 121/121, `bash -n Scripts/build_app.sh` and `git diff --check` passed, and the signed build/install completed. Both installed binaries strictly verify against the Apple Development chain, use TeamIdentifier `973KFG9CL9`, contain the matching App Group entitlement, and have no debugging entitlement. `containermanagerd` approved App Group access for both bundle identifiers; the shared snapshot was rewritten with the real `1/12` daily progress while the primary and backup history hashes remained unchanged; `chronod` successfully rebuilt both annual and quarterly timelines, and the quarterly live archive contains `1/12` and the 90-day total `108` rather than the former `0/8` placeholder. Two independent adversarial reviews found and then confirmed closure of install rollback, registration postcondition, regression-test coverage, data-evidence, and documentation issues.
- Handoff notes: The repaired build 6 is installed at `/Applications/SitRight.app` as the only active/running copy selected by PlugInKit. LaunchServices may retain inactive development/backup registrations, so checks should resolve the actual path rather than assume a bundle ID is unique. The rejected ad-hoc build is backed up at `build/SitRight-before-team-signed-build6.app`; the historical recovery backup remains at `/Users/leon/Documents/SitRight-Recovery-20260723-095011/`. The build script now refuses to replace `/Applications/SitRight.app` unless both the source App and Widget have TeamIdentifier `973KFG9CL9`, stages and verifies the candidate before same-volume replacement renames, rolls back on post-replacement failure, and verifies the same unique PlugInKit registration postcondition for both successful installation and rollback restoration.

### TASK-20260723-widget-history-display-recovery

- Status: Done
- Goal: Recover the existing SitRight activity information after the new quarterly widget appeared empty.
- Impacted areas: Installed-app process identity, App Group activity history, Widget snapshot/timeline cache, and recovery backup.
- Verification: The App Group primary history remained valid with 20 days of records from 2026-06-30 through 2026-07-23. At snapshot time its SHA-256 matched the recovery copy at `b80a698f1346643a508c0ca820a64229971da0e747f4aecbca0bd354144545cd`; the later live-file hash changed only because the running app recorded 2026-07-23 cycle state changes, while all earlier days stayed object-identical. A decoder compiled from the production shared models reported 18 qualified days in the rolling 90-day window, 107 total qualified activities, 14 this week, and an 18-day streak. The unintended `build/SitRight.app` process and duplicate active plug-in registration were removed, `/Applications/SitRight.app` was launched as the sole main process, and `chronod` reported successful external-trigger timeline reloads for both `SitRightQuarterActivityWidget` and `SitRightActivityWidget`.
- Handoff notes: No history payload was replaced. A durable point-in-time copy of the App Group primary/backup/snapshot plus the app-container fallback, preferences, and checksum manifest is stored at `/Users/leon/Documents/SitRight-Recovery-20260723-095011/`; an additional working copy remains at `build/SitRight-data-recovery-20260723-095011/`. Keep the installed app as the sole running SitRight main process when checking packaged Widget behavior, and never restore this snapshot over a newer live history without comparing timestamps and hashes first.

### TASK-20260722-quarter-widget

- Status: Done
- Goal: Add a separate large SitRight widget for the rolling last 90 days while preserving the existing annual widget identity and behavior.
- Impacted areas: Shared Widget kinds and reloads, WidgetKit registration and heatmap presentation, regression coverage, README, project context, and the shared App/Widget build number.
- Verification: `swift test` passed 120/120; `./Scripts/build_app.sh` completed with `** BUILD SUCCEEDED **`; strict App/Widget codesign, arm64 architecture, matching App Group entitlements, packaged binary kind strings, installed-build equality, and system plug-in registration passed. After installing build 6 and restarting Widget services, `chronod` reported two descriptors: the large-only `SitRightQuarterActivityWidget` and medium/large `SitRightActivityWidget`. Two independent adversarial reviews completed and the confirmed documentation findings were repaired.
- Handoff notes: `SitRightActivityWidget` remains stable for existing annual widgets; `SitRightQuarterActivityWidget` is large-only and shares the existing snapshot/history formats. Build 6 is installed at `/Applications/SitRight.app`; the replaced build 5 is backed up at `build/SitRight-before-build6-20260723-093506.app`.

### TASK-20260718-status-popover-memory

- Status: Done
- Goal: Stop the persistent status popover from entering a SwiftUI preferred-size/segmented-picker feedback loop that drives the main process to high CPU and unbounded memory growth.
- Impacted areas: Native status item/popover hosting, visibility-gated menu-panel engine refreshes, tab resize notifications, native status-button refresh coalescing, and focused regression tests.
- Verification: `swift test` passed 138/138; `./Scripts/build_app.sh` produced and validated the signed Release App/Widget package; `git diff --check` passed. A closed-popover 10-minute run averaged 0.90% CPU and held 25-26 MB physical footprint. After 20 app-scoped status-item open actions, a second 10-minute run averaged 0.96% CPU and ended at 45.5 MB footprint with 78,472 heap nodes, down from 78,986 at the stress boundary. The one-time graphics peak was 124.9 MB. Final `sample` contained no recurring segmented-picker, preferred-size, or popover `sizeThatFits` stack.
- Handoff notes: The non-animated persistent popover, reminder scheduling, shared storage, Widget behavior, user settings, and unrelated mixed-worktree changes were preserved. The final build is running from `build/SitRight.app` and was not installed over `/Applications/SitRight.app`. Fifty interactive tab switches could not be automated because the local computer-use runtime was unavailable and macOS Accessibility did not expose the transient popover as a retained window; no coordinate-based UI automation was attempted.

### TASK-20260715-audit-remediation

- Status: Done
- Goal: Implement the approved audit remediation for storage recovery/migration, reminder state and DST scheduling, system-status UI, accessibility, and Release packaging reliability.
- Impacted areas: Shared history storage, ReminderEngine/StatsStore, notification and launch-at-login services, status item accessibility, project/build configuration, and regression tests.
- Verification: `swift test` and `swift test --parallel` passed 133/133; the true two-process storage test and five repeated stress runs passed; `./Scripts/build_app.sh` produced a signed arm64 App/Widget pair with no LLVM coverage/profiling sections; real build-lock contention exited 75 before XcodeGen/build; `bash -n Scripts/build_app.sh` and `git diff --check` passed.
- Handoff notes: Existing mixed worktree changes were preserved and `project.yml` remained the Xcode source of truth. Notification-settings, login-item approval, and VoiceOver behavior still need interactive packaged smoke checks because they alter or depend on current macOS system state.

### TASK-20260713-trustworthy-activity-counting

- Status: Done
- Goal: Replace the always-on completion counter with idempotent reminder-cycle completion, rate-limited manual activity, reminder response rate, and compatible App/Widget statistics.
- Impacted areas: Activity history schema and migration, reminder delivery/state lifecycle, Today/settings UI, Widget metrics, shared snapshots, and regression tests.
- Verification: Targeted `ReminderEngineTests` passed 42/42 and `ActivityHistoryTests` passed 14/14; full `swift test` and `swift test --parallel` each passed 103/103; the signed App/Widget package built successfully, overwrote `/Applications/SitRight.app`, and restarted from that installed path. The live status item was enabled with value “非提醒时段”; repeated semantic open/close checks observed a stable 396×622 popover, about 119 ms to visible and 18 ms to close. `git diff --check` passed.
- Handoff notes: Existing `completedCount` values remain preserved as unclassified legacy records and do not enter the new reminder response-rate numerator or denominator. The manual smoke test did not invoke either activity action or modify activity history. Pixel capture of the transient popover was unavailable on its negative-coordinate display, so fixed action-slot geometry is guarded by the compiled SwiftUI layout and regression suite rather than a screenshot artifact.

### TASK-20260713-end-of-day-status

- Status: Done
- Goal: Show the non-reminder status instead of a cross-night wall-clock countdown when the current workday has too little allowed time left for another reminder.
- Impacted areas: ReminderEngine schedule-state classification, menu bar status behavior, reminder boundary regression tests, and packaged app runtime.
- Verification: The targeted failing regression test now passes; `ReminderEngineTests` passed 18/18; full `swift test` passed 66/66; `./Scripts/build_app.sh` completed a signed Release App/Widget build and installed it to `/Applications`; the restarted process exposed status value “非提醒时段”; `git diff --check` passed.
- Handoff notes: The scheduling date is unchanged and still carries remaining allowed-work time into the next workday. Only the display state changes to `outsideHours` until that workday begins; the user’s 45-minute interval and other saved settings were preserved.

### TASK-20260713-menu-bar-interaction-latency

- Status: Done
- Goal: Give the menu bar icon immediate native pressed feedback, open a prewarmed popover without animation, and keep the “已活动” action row stationary while completion feedback appears.
- Impacted areas: App entry point, native status item/popover hosting, menu panel celebration feedback, and packaged macOS interaction behavior.
- Verification: `swift test` passed 62/62; `./Scripts/build_app.sh` produced a validated Release App with the Widget embedded; the packaged test app launched and exposed the expected SitRight status item through macOS accessibility; `git diff --check` passed.
- Handoff notes: Completion feedback now replaces the fixed header subtitle/icon rather than inserting a new row. The test app was not installed and was terminated after validation, leaving the user’s existing `/Applications/SitRight.app` process untouched.

### TASK-20260713-regression-test-hardening

- Status: Done
- Goal: Audit the current SitRight behavior and add stable automated regression tests for high-risk logic and persistence paths without introducing new CI or wrapper scripts.
- Impacted areas: Reminder scheduling/state, pause persistence, settings normalization/compatibility, stats migration and recovery, shared App/Widget snapshot writes, and source-level packaging contracts.
- Verification: Independent Test Agent passed `swift test` (62/62), `swift test --parallel` (62/62), `swift test --enable-code-coverage` (62/62), `./Scripts/build_app.sh`, final product signing/Bundle ID/App Group entitlement checks, and `git diff --check`.
- Handoff notes: Fixed lunch/work-boundary scheduling, due-state consistency during setting changes, and Widget snapshot retry after failed writes. Real notification permission UI, desktop Widget rendering/cross-process refresh, and launch-at-login remain packaged manual smoke tests because exercising them changes macOS system state.

### TASK-20260710-reliability-hardening

- Status: Done
- Goal: Implement the approved reminder-state, persistence, shared-storage, notification, UI, documentation, and validation hardening plan.
- Impacted areas: ReminderEngine, StatsStore, shared App/Widget storage, Widget synchronization, settings UI, build checks, tests, and agent documentation.
- Verification: `swift test` passed 41 tests; `./Scripts/build_app.sh` produced a validated Release app with Widget and App Group entitlements; shell/plist checks and `git diff --check` passed.
- Handoff notes: Existing user changes were preserved. Real notification-denial and desktop-Widget UI flows remain manual because exercising them would modify the current macOS notification and desktop configuration.
