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

### TASK-20260718-apple-inspired-activity-reminder

- Status: Done
- Goal: Redesign SitRight around a rolling Apple-inspired 50/1 activity cadence with a verified 60-second guide, independent reminder-opportunity timing, actionable notifications, and an adjustable daily activity goal.
- Impacted areas: Reminder state machine and runtime persistence, notification actions, activity-history schema and metrics, Today/settings/popup UI, Widget snapshots and presentation, accessibility, and migration/regression coverage.
- Verification: `swift test` passed 119/119; `./Scripts/build_app.sh` completed with `** BUILD SUCCEEDED **` and produced `build/SitRight.app`; `git diff --check` passed; architecture and product adversarial reviews completed with confirmed findings repaired and regression coverage added.
- Handoff notes: Preserve existing saved interval and delivery preferences; apply 50 minutes, notifications on, sound off, and strong popup off only to fresh installs. Do not edit the generated Xcode project. Packaged notification authorization/action, VoiceOver, lock/sleep, and widget visual checks remain manual follow-up because they require running the signed app and changing system state.

## Done

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
