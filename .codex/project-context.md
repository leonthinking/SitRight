# SitRight Project Context

This file captures repo facts that future agents should rely on instead of rediscovering basic structure.

## Product Baseline

SitRight 坐正 is a macOS menu bar reminder app for posture and short activity breaks during long desk work.

Current first-version capabilities include:

- Menu bar countdown.
- Reminder popup and optional system notification.
- Complete a delivered reminder once per reminder cycle, or record a separately classified manual activity while running.
- Snooze for 5 minutes.
- Pause, resume, and pause for today.
- Workday, work-hour, and lunch-break scheduling.
- Daily reminder-completion target, reminder response rate, manual activity count, and legacy unclassified history.
- Launch-at-login toggle.
- WidgetKit desktop widget for progress/history and activity completion when a reminder is due.

The app is intentionally lightweight and local-first. There is no backend service in this repository.

## Build and Configuration

- `Package.swift` targets macOS 14 and Swift 6, with executable target `SitRight` and test target `SitRightTests`.
- `project.yml` is the source of truth for the generated Xcode project.
- The generated Xcode project contains:
  - `SitRight` app target.
  - `SitRightWidgetExtension` app-extension target.
  - `SitRightTests` unit-test bundle.
- `Scripts/build_app.sh` runs XcodeGen, builds Release through `xcodebuild`, stages the app, signs when an identity is available, verifies signatures, copies to `build/SitRight.app`, and removes derived data unless `SITRIGHT_KEEP_DERIVED_DATA=1`.
- `.gitignore` excludes generated and local outputs including `SitRight.xcodeproj/`, `.build/`, `build/`, and `DerivedData/`.

## Runtime Composition

`Sources/SitRightApp.swift` is the app entry point.

- `AppDelegate` sets activation policy to `.accessory` so the app has no Dock icon, creates `AppContainer`, and retains `StatusBarController`.
- `StatusBarController` owns a native `NSStatusItem` and a persistent `NSPopover` that hosts the existing SwiftUI menu panel.
- The popover is pre-sized, does not animate when shown, and reuses its hosting controller between clicks so opening the menu does not rebuild the panel.
- `MenuBarStatusLabel` remains the shared SwiftUI status label and is embedded in the native status-item button through a click-through `NSHostingView`.
- `AppContainer` owns and wires the long-lived app services.

`Sources/AppContainer.swift` builds:

- `SettingsStore`
- `StatsStore`
- `NotificationManager`
- `ReminderPresenter`
- `WidgetSyncController`
- `ReminderEngine`

`ReminderEngine.start()` is called during container initialization.

## Core Behavior

`ReminderEngine` is the central runtime state machine.

- Published state includes current time, next reminder date, run state, active reminder text/cycle, and temporary celebration text.
- Run states are `running`, `paused`, `outsideHours`, `disabled`, and `due`.
- A one-second timer drives the in-memory countdown through `tick()`; shared files are only updated when Widget-relevant fields change.
- Scheduling uses `SchedulePolicy` inside `ReminderEngine`.
- `completeCurrentReminder()` only accepts a pending cycle and relies on its stable ID for idempotency.
- `recordManualActivity()` is available only while reminders are running with no pending response; it resets the timer and remains locked for one full reminder interval.
- Snooze is currently 5 minutes by default and reuses the current cycle, so repeated snoozes do not add response-rate opportunities.
- Popup actions are handled through `ReminderAction`.
- Indefinite and timed pause state is persisted by `ReminderSessionStateStore` and restored after relaunch.
- Popup and system notification delivery for one trigger share a single cycle. A popup establishes the opportunity immediately; notification-only mode establishes it only after confirmed delivery and keeps a menu-panel completion entry until the next cycle.
- A pending cycle expires when the next cycle begins, work hours end, or the date changes. Pause and reminder disable settle it as skipped. Notification failure without a popup creates no opportunity.
- Pending and snoozed cycles are restored after relaunch without changing their ID or original deadline; stale pending cycles are settled once.
- When the remaining interval no longer fits in the current workday, the next reminder keeps its carried-over allowed-work time but the UI enters `outsideHours` instead of showing a cross-night wall-clock countdown. The countdown resumes at the next workday start.

Scheduling depends on `AppSettings`:

- `remindersEnabled`
- `intervalMinutes`
- `workdaysOnly`
- `workStartMinutes`
- `workEndMinutes`
- `lunchPauseEnabled`
- `lunchStartMinutes`
- `lunchEndMinutes`

Non-schedule settings should not cause reminder rescheduling.

## Persistence and Shared Data

`SettingsStore` persists `AppSettings` as JSON in `UserDefaults` key `sitright.settings.v1`.

`StatsStore` uses `ActivityHistoryStore` as the current stats source and still writes the legacy daily stats key `sitright.dailyStats.v1` for compatibility. It refreshes the current day only across a date boundary rather than rereading history every second.

Shared App/Widget storage lives in `Sources/Shared`:

- Packaged App/Widget processes require the App Group. Application Support fallback is limited to unbundled SwiftPM development runs.
- App Group identifier: `973KFG9CL9.com.leon.SitRight`.
- `ActivityHistoryStore.fileName`: `SitRightActivityHistory.json`.
- `ActivityHistoryStore.backupFileName`: `SitRightActivityHistory.backup.json`.
- `WidgetSnapshotStore.fileName`: `SitRightWidgetSnapshot.json`.

Activity-history updates use both an in-process lock and a cross-process file lock. Valid history is backed up before replacement; an unreadable primary file is preserved and restored from the backup when possible.

Each `ActivityDay` retains the legacy `completedCount` compatibility field and additionally stores `ReminderCycleRecord` and `ManualActivityRecord` arrays. Derived metrics keep reminder completions/opportunities, response rate, manual activity, and legacy unclassified counts separate. Old `completedCount` data remains eligible for historical week/streak/heatmap continuity but never enters the new reminder response rate; manual activity enters neither reminder progress nor the historical qualified-activity metric.

The App and Widget must agree on shared model encoding. Treat changes to shared Codable types as compatibility-sensitive.

## Widget Extension

The widget code lives in `Widget/`.

- `SitRightWidgetProvider` loads `WidgetSnapshot` and `ActivityHistory`.
- Supported widget families are `.systemMedium` and `.systemLarge`.
- The widget is display-only and shows reminder completion, response rate, manual activity, week/streak statistics, and a one-year qualified-activity heatmap.
- `WidgetSyncController` writes and reloads only when Widget-relevant snapshot fields change.

Widget behavior depends on matching:

- App Group entitlements in both app and widget.
- `SitRightWidgetKind.activity`.
- Codable shapes in `WidgetSnapshot` and `ActivityHistory`.

## Tests

Current tests cover:

- `SettingsStoreTests`: defaults, normalization, persistence, callback behavior, schedule-change detection.
- `ReminderEngineTests`: pause restoration, due-state cleanup, delivery success/failure, reminder-cycle idempotency, manual-activity rate limiting, restart recovery, work-hour/lunch/weekend scheduling, and snooze reuse.
- `StatsStoreTests`: date-boundary refresh, cycle/manual persistence, cross-day settlement, compatibility mirroring, and storage-error surfacing.
- `ActivityHistoryTests`: daily counts, reminder-cycle outcomes/response metrics, legacy migration, week/streak qualification, tolerant decoding, backup recovery, and concurrent idempotent file persistence.
- `TimeFormattingTests`: countdown and menu bar fixed-width formatting.
- `WidgetSnapshotTests`: tolerant legacy decoding, trusted metric publication, response/progress calculation, and duplicate-write prevention.

There is no automated test coverage yet for:

- SwiftUI view rendering.
- Real system notification delivery/permission UI.
- Launch-at-login behavior.
- Full WidgetKit timeline rendering.

Use this gap when deciding whether a manual packaged build is needed for a change.

## Compatibility Notes

- `AppSettings` has a custom decoder with defaults for missing fields. Preserve this pattern when adding settings.
- `AppSettings.normalized()` clamps user-controlled values. Extend normalization with tests when adding numeric settings.
- `ActivityHistory`, `ActivityDay`, and `WidgetSnapshot` use default-tolerant decoding. Preserve that compatibility when adding stored fields.
- Launch-at-login is expected to fail or be misleading when running outside a packaged app; UI already reports that case.
