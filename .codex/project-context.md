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
- A display-only WidgetKit desktop widget for today progress, reminder state, and rolling 90-day activity history.
- A persisted in-app Simplified Chinese / English preference shared by app-owned surfaces, notifications, and Widget content.

The app is intentionally lightweight and local-first. There is no backend service in this repository.

## Build and Configuration

- `Package.swift` targets macOS 14 and Swift 6, with executable target `SitRight` and test target `SitRightTests`.
- Sparkle is pinned to 2.9.2 in `Package.swift`, `Package.resolved`, and `project.yml`.
- `project.yml` is the source of truth for the generated Xcode project.
- The generated Xcode project contains:
  - `SitRight` app target.
  - `SitRightWidgetExtension` app-extension target.
  - `SitRightTests` unit-test bundle.
- `Scripts/build_app.sh` runs XcodeGen, builds Release through `xcodebuild`, stages the app, signs Sparkle's XPC/Updater/Autoupdate/Framework in nested order before the Widget and App, verifies signatures, copies to `build/SitRight.app`, and removes derived data unless `SITRIGHT_KEEP_DERIVED_DATA=1`. When installation is explicitly enabled, it removes all noncanonical physical registrations, moves the build source into the recoverable transaction under a non-App suffix, and requires three consecutive unique observations of the canonical Applications Widget before committing. The ordinary non-install build retains `build/SitRight.app`, marks `build/` as excluded from metadata indexing, and deregisters transient products so a local candidate does not silently replace the installed Widget during discovery.
- `Scripts/package_dmg.sh` serializes against the app build flow, rebuilds the Release app without installing it, and requires matching TeamIdentifier/App Group contracts for the App and Widget plus the same TeamIdentifier across all Sparkle components. It creates a draggable compressed HFS+ candidate DMG whose top level contains only `SitRight.app` and `Applications`, verifies the image, read-only mounted contents, mounted signatures, and checksum, then publishes the DMG and `.sha256` pair without overwriting an existing valid pair on pre-publication failure.
- `Scripts/package_update.sh` prepares but never uploads a signed community-update DMG, app-only ZIP, signed appcast, and SHA-256 manifest from a `git archive` snapshot of the captured committed arm64 candidate; it snapshots Release Notes, downloads the fixed Sparkle 2.9.2 official tool archive with its pinned SwiftPM checksum, binds individual tool hashes into the manifest, and rechecks the source tree before promoting assets. `Scripts/publish_update_release.sh` is a separate confirmation-gated GitHub operation pinned to `leonthinking/SitRight`; it snapshots all upload assets and Release Notes, independently reacquires and verifies the same Sparkle tools, requires an authenticated `gh`, a matching pushed tag, an increasing build number relative to GitHub's actual `latest` Release, complete reverified assets, and uses a verified Draft before the final non-Prerelease publication step.
- The standalone DMG script does not notarize or staple its output, so its ordinary output remains an internal-test artifact. A versioned image produced through the explicitly authorized community-release flow may be published for manual GitHub download, but it is still not Developer ID signed, notarized, stapled, or Gatekeeper-trusted.
- `.gitignore` excludes generated and local outputs including `SitRight.xcodeproj/`, `.build/`, `build/`, and `DerivedData/`.

## Runtime Composition

`Sources/SitRightApp.swift` is the app entry point.

- `AppDelegate` starts with activation policy `.accessory` so the resting app has no Dock icon, creates `AppContainer`, and retains `StatusBarController`.
- `SettingsWindowActivationController` temporarily promotes the app to `.regular` while a standard Settings window is presented, exposing the native application menu and `Command-H`. Hiding keeps `.regular` so macOS can restore the Settings window through `Command-Tab`; closing the last standard window restores `.accessory` while the status item and reminder engine keep running.
- After `applicationDidFinishLaunching`, `AppDelegate` starts the single `UpdateController`; Sparkle is not started during container construction.
- `StatusBarController` owns a native `NSStatusItem` and a persistent `NSPopover` that hosts the existing SwiftUI menu panel.
- The popover is pre-sized, does not animate when shown, and reuses its hosting controller between clicks so opening the menu does not rebuild the panel.
- `MenuBarStatusLabel` remains the shared SwiftUI status label and is embedded in the native status-item button through a click-through `NSHostingView`.
- `AppContainer` owns and wires the long-lived app services.

`Sources/AppContainer.swift` builds:

- `SettingsStore`
- `StatsStore`
- `NotificationManager`
- `UpdateController`
- `ReminderPresenter`
- `WidgetSyncController`
- `ReminderEngine`

`ReminderEngine.start()` is called during container initialization.

`AppSettings.language` is an additive, default-tolerant language preference.
Existing settings without the field continue in Simplified Chinese. Language
changes update product copy and the shared Widget snapshot without entering the
reminder-schedule change set, so cadence and activity data are not reset. Native
macOS menu commands and Sparkle's standard updater UI may continue to follow the
system language. The selected copy language preserves the current region's hour
cycle and first weekday, and app-owned SwiftUI controls select copy explicitly so
the same behavior works in both the packaged App and `swift run` development path.

The Settings scene uses a fixed 520 pt content width with native vertical
resizing. Its 900 pt default height is raised once from known legacy defaults,
clamped to the visible screen, and otherwise preserves a user-adjusted height.
Forms continue to scroll when the window is shortened or accessibility and
dynamic content require more room.

## Community Update Flow

- Update source: `https://github.com/leonthinking/SitRight/releases/latest/download/appcast.xml`.
- Sparkle performs a scheduled check at most every 24 hours. Automatic checks use a gentle menu-panel indicator; user-initiated checks use Sparkle's standard UI.
- Automatic downloading is disallowed. Downloads and installation require explicit user confirmation. Update archives and the appcast, including embedded reviewed release notes, are EdDSA signed; signature failures cannot downgrade to unsigned updates.
- The Settings raw value `about` is stable. Existing `general`, `notifications`, and legacy `schedule` routing remain compatible.
- The public EdDSA key is embedded in `AppBundle/Info.plist`. The matching private key is stored only in the local Keychain account `com.leon.SitRight` and requires an offline recovery backup before the bootstrap Release.
- The GitHub community preview is not Developer ID signed or notarized. The first update-enabled build must still be installed manually; subsequent builds can update in app.
- `package_update.sh` presents only the ZIP to `generate_appcast`, then adds the manually installable DMG after the signed feed is verified. `publish_update_release.sh` requires the GitHub Release notes to match the notes hash recorded for the signed appcast and revalidates the local and uploaded assets. It records the final Draft-to-public transition in persistent local recovery state; a failed transition is restored to Draft when GitHub is reachable, while an unconfirmable remote state blocks later publication for manual resolution.
- No GitHub Actions release workflow is used. Apple and Sparkle private keys must never enter the repository, logs, or GitHub Release assets.

## Open Source and Community

- SitRight-owned source is distributed under the repository-root MIT License; the same text is bundled for offline viewing in the About settings pane.
- The About pane links to the public source repository, privacy/security guidance, private vulnerability reporting, and dedicated GitHub Issue forms for support, feature requests, and bug reports. It also shows the bundled Sparkle 2.9.2 third-party notices.
- Activity history and settings remain local to the user's device and App Group. SitRight does not automatically upload them to the developer or a remote service, and it does not collect or upload crash reports or diagnostic logs.
- There is no in-app diagnostic-log reader or uploader. Do not add a dead “error log” row without separately designing its privacy, redaction, retention, and user-consent boundaries.
- Before publishing a build that contains these community links, all legal, privacy, security, support, contribution, Issue Form/config, and PR-template files must exactly match the remote `main` branch. The repository must remain public with Issues and Private Vulnerability Reporting enabled.
- Tracked project documentation must not contain user-home paths, account identifiers, recovery locations, real activity evidence, or hashes derived from private user data.

## Core Behavior

`ReminderEngine` is the central runtime state machine.

- Published state includes current time, next reminder date, run state, active reminder text/cycle, and temporary celebration text.
- Run states are `running`, `paused`, `outsideHours`, `disabled`, and `due`.
- A one-second timer drives the in-memory countdown through `tick()`; shared files are only updated when Widget-relevant fields change.
- Scheduling uses `SchedulePolicy` inside `ReminderEngine`.
- `completeCurrentReminder()` only accepts a pending cycle and relies on its stable ID for idempotency.
- `recordManualActivity()` is available while reminders are running with no pending response. A completed proactive guide normally preserves the existing reminder deadline while its eligible 60 seconds continue advancing the cadence clock.
- If a proactive guide completes with no more than 10 minutes remaining, it satisfies the upcoming reminder without creating a reminder opportunity and starts a fresh interval. A prompted guide completion always resolves its reminder cycle and starts a fresh interval.
- Cancelling a proactive guide records no activity and preserves the cadence; if the cadence became due during the guide, normal reminder delivery resumes after dismissal.
- A proactive guide that crosses out of an allowed work period still records the completed activity, while cadence reset and the completion feedback follow the existing work-schedule rules instead of promising an unchanged reminder time.
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
- App and Widget must both be signed with TeamIdentifier `973KFG9CL9`; an ad-hoc signature can carry the entitlement text but macOS rejects its runtime App Group access.
- `ActivityHistoryStore.fileName`: `SitRightActivityHistory.json`.
- `ActivityHistoryStore.backupFileName`: `SitRightActivityHistory.backup.json`.
- `WidgetSnapshotStore.fileName`: `SitRightWidgetSnapshot.json`.

Activity-history updates use both an in-process lock and a cross-process file lock. Valid history is backed up before replacement; an unreadable primary file is preserved and restored from the backup when possible.

Each `ActivityDay` retains the legacy `completedCount` compatibility field and additionally stores `ReminderCycleRecord` and `ManualActivityRecord` arrays. Derived metrics keep reminder completions/opportunities, response rate, manual activity, and legacy unclassified counts separate. Old `completedCount` data remains eligible for historical week/streak/heatmap continuity but never enters the new reminder response rate; manual activity enters neither reminder progress nor the historical qualified-activity metric.

The App and Widget must agree on shared model encoding. Treat changes to shared Codable types as compatibility-sensitive.

## Widget Extension

The widget code lives in `Widget/`.

- `SitRightWidgetProvider` loads `WidgetSnapshot` and `ActivityHistory`.
- The only registered Widget is the rolling 90-day `SitRightQuarterActivityWidget`, which supports `.systemLarge` only.
- The retired annual identity `SitRightActivityWidget` remains reserved in source but is not registered or reloaded. Existing annual placements cannot migrate to the quarterly kind and must be removed by the user.
- The quarterly Widget is display-only and shows the daily goal, reminder completions, qualified proactive activity, week/streak statistics, current reminder status, and a qualified-activity heatmap.
- Heatmap intensity represents each day's progress against its persisted daily-target snapshot: below 25%, 25–49%, 50–99%, and at least 100%. A positive legacy day without a target snapshot uses only the lowest intensity rather than inferring historical completion from today's target.
- The quarterly Widget shows localized month markers and a completion legend using the original compact square-cell layout.
- Leading padding before the rolling 90-day range and the remaining future weekdays through the end of today's calendar week use matching non-statistical decorative-gray placeholders, keeping both outer weeks visually complete and symmetric. Their fill is deliberately lighter than a real inactive day so they do not imply missed activity. These decorative cells have no date and never enter activity totals, active/completed days, streaks, month markers, persistence, or accessibility summaries. Today is outlined. Inactive paused/non-workdays use a neutral outline. Dates without eligibility/history remain visually indistinguishable from ordinary inactive dates because no first-tracked date is persisted.
- `WidgetSyncController` writes only when Widget-relevant snapshot fields change, then reloads the quarterly Widget kind.
- `WidgetSnapshot.language` carries the app language across the App Group boundary; missing or unknown values fall back to Simplified Chinese without invalidating the remaining snapshot.

Widget behavior depends on matching:

- App Group entitlements in both app and widget.
- The stable values in `SitRightWidgetKind.allActivityKinds`.
- Codable shapes in `WidgetSnapshot` and `ActivityHistory`.

## Tests

Current tests cover:

- `SettingsStoreTests`: defaults, normalization, persistence, callback behavior, schedule-change detection.
- `ReminderEngineTests`: pause restoration, due-state cleanup, delivery success/failure, reminder-cycle idempotency, proactive cadence preservation and 10-minute protection, restart recovery, work-hour/lunch/weekend scheduling, and snooze reuse.
- `StatsStoreTests`: date-boundary refresh, cycle/manual persistence, cross-day settlement, compatibility mirroring, and storage-error surfacing.
- `ActivityHistoryTests`: daily counts, reminder-cycle outcomes/response metrics, legacy migration, week/streak qualification, tolerant decoding, backup recovery, and concurrent idempotent file persistence.
- `TimeFormattingTests`: countdown and menu bar fixed-width formatting.
- `WidgetSnapshotTests`: tolerant legacy decoding, trusted metric publication, response/progress calculation, and duplicate-write prevention.
- `UpdateControllerTests`: feed/public-key configuration, delayed lifecycle start, gentle reminder state, manual session feedback, and disabled misconfiguration behavior.
- `PackagingContractTests`: Sparkle version/feed/entitlement contracts, nested signing, DMG contents, local appcast assets, publication confirmation, and rollback ordering.

There is no automated test coverage yet for:

- Real system notification delivery/permission UI.
- Launch-at-login behavior.
- Full WidgetKit timeline rendering.
- A real two-version Sparkle replacement/relaunch on a clean macOS account.

Use this gap when deciding whether a manual packaged build is needed for a change.

## Compatibility Notes

- `AppSettings` has a custom decoder with defaults for missing fields. Preserve this pattern when adding settings.
- `AppSettings.normalized()` clamps user-controlled values. Extend normalization with tests when adding numeric settings.
- `ActivityHistory`, `ActivityDay`, and `WidgetSnapshot` use default-tolerant decoding. Preserve that compatibility when adding stored fields.
- `SMAppService.Status.notFound` means ServiceManagement could not find the service; it is not proof that the process is unbundled. The UI keeps registration retry, status refresh, and System Settings recovery available without changing the persisted settings format.
