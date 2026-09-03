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

No tracked tasks yet.

## Done

### TASK-20260903-system-default-language

- Status: Done
- Goal: Add a persisted `system_default` language preference, make it the default, and resolve all app-owned, notification, and Widget copy to Simplified Chinese on Chinese systems or English otherwise.
- Impacted areas: App language resolution, settings compatibility, notification categories, Widget snapshots, settings presentation, README/project context, packaged App validation, and regression coverage.
- Verification: `swift test --disable-sandbox` passed 284/284 with a repository-local module cache; `git diff --check` passed; the signed App/Widget build and transaction install to `/Applications/SitRight.app` succeeded with TeamIdentifier `973KFG9CL9` and the required App Group. The installed Settings window preserved the existing explicit English preference and exposed exactly `Automatic (System Default)`, `简体中文`, and `English`. Two independent adversarial reviews found and drove fixes for non-Chinese month-label mixing and legacy Widget status-language mixing; final re-reviews found no confirmed issues.
- Handoff notes: New, missing, and unknown App settings use the stable raw value `system_default`; existing explicit `zh-Hans` and `en` values remain unchanged. Automatic mode resolves Chinese system interface languages to Simplified Chinese and all other interface languages to English while preserving regional hour-cycle and week-start preferences. Changing the preference does not reset cadence or activity data. Runtime changes to the macOS primary language rely on the normal app/system refresh or relaunch path rather than a custom hot-switch observer. Version `0.2.8 (13)`, Git state, and the unrelated untracked `output/` directory remain unchanged; no commit, push, tag, DMG, or Release was performed.

### TASK-20260903-english-layout-adaptation

- Status: Done
- Goal: Make the English activity-guide window fully readable at its normal size and audit all app-owned English surfaces for missing localization or layout regressions.
- Impacted areas: Reminder panel sizing and SwiftUI layout, bilingual presentation coverage, notifications/menu/settings/Widget/update/accessibility copy audit, packaged App visual acceptance, and project documentation.
- Verification: `swift test --disable-sandbox` passed 280/280 and `git diff --check` passed. The signed App/Widget build and transaction install succeeded with TeamIdentifier `973KFG9CL9` and the required App Group. Production-hosting tests cover every normal Chinese/English reminder, guide, completion message and action within the fixed horizontal bounds; the accessibility fallback proves the cancel action intersects the real scroll viewport after scrolling. The installed English menu, General Settings page, Widget, and 1-minute guide were inspected on the desktop; the guide displayed all text, countdown, and cancel action at its normal size without a scrollbar. Two independent adversarial reviews found and drove fixes for scroll reachability, timer-ring clipping, midnight formatting, cross-language error details, count grammar, time-cycle formatting, and status wording; final reviews found no remaining confirmed issues.
- Handoff notes: Normal reminder panels remain fixed at 420 pt wide with a 360 pt minimum height, while small screens and accessibility text sizes retain the internal scroll fallback. Automatic Hosting Controller sizing remains disabled and countdown ticks do not remeasure the panel. Reminder cadence, settings/history/Widget persistence, version `0.2.8 (13)`, and the unrelated untracked `output/` directory are unchanged. The desktop acceptance activity was canceled before completion. No commit, push, tag, DMG, or Release was performed.

### TASK-20260824-settings-value-controls

- Status: Done
- Goal: Unify reminder interval, daily target, schedule times, and language as complete trailing value pickers so values and disclosure indicators remain visually grouped and right-aligned.
- Impacted areas: General Settings presentation, localized value copy, option compatibility, accessibility, regression coverage, and packaged App visual acceptance.
- Verification: `swift test --disable-sandbox` passed 271/271; `./Scripts/build_app.sh` passed and the transaction installer replaced `/Applications/SitRight.app` after verifying TeamIdentifier `973KFG9CL9` and the required App Group; `git diff --check` passed. Production-hosting coverage verified aligned picker edges, complete values, and no clipping in Simplified Chinese and English. The installed `0.2.8 (13)` Settings window was opened and visually checked: daily target displays the complete `10 次` value and all trailing picker controls align consistently. Two independent reviews found no remaining settings-compatibility, layout, keyboard, or accessibility issues.
- Handoff notes: Existing settings storage, immediate persistence, legacy off-step time/interval selections, reminder behavior, fixed window width, and unrelated workspace changes are preserved. The generated Xcode project and build products remain untracked; `output/` was not modified. No version change, commit, push, tag, or Release was performed.

### TASK-20260824-in-app-language

- Status: Done
- Goal: Add an in-app Simplified Chinese / English language preference that updates the app, reminders, notifications, and Widget without changing reminder or activity-history behavior.
- Impacted areas: App settings compatibility, user-facing copy, notification categories, Widget snapshot/display, accessibility, README, project context, and regression coverage.
- Verification: `swift test --disable-sandbox` passed 272/272; `./Scripts/build_app.sh` passed; both packaged targets contain valid English and Simplified Chinese string resources; `git diff --check` passed. Independent implementation and release reviews closed notification concurrency, locale, runtime copy, development-build version text, layout, and compatibility findings.
- Handoff notes: Existing users remain on Simplified Chinese until they choose English. The additive language field tolerates missing and unknown values; changing it does not reset cadence or activity data. No app installation, version change, Git commit, push, or release was performed.

### TASK-20260812-heatmap-symmetric-edge-fill

- Status: Done
- Goal: Render the rolling-range leading alignment cells and the future cells after today with matching lighter decorative-gray placeholders, making the quarterly heatmap's outer weeks visually complete and symmetric without changing its 90-day statistics.
- Impacted areas: Quarterly Widget cell rendering, heatmap presentation/view contracts, README, project context, versioned packaged installation, and visual smoke verification.
- Verification: Focused `HeatmapPresentationTests` passed 14/14 and `WidgetSnapshotTests` passed 16/16; the full Swift suite passed 252/252. `bash -n Scripts/build_app.sh` and `git diff --check` passed. The signed `0.2.8 (13)` App/Widget candidate built and installed successfully with TeamIdentifier `973KFG9CL9` and the required App Group; both bundles report the same version, strict signature checks pass, and PlugInKit resolves exactly one canonical `/Applications` extension. Two independent adversarial reviews completed; the confirmed indistinguishable-placeholder and task-documentation findings were fixed, with final re-review finding no remaining P0-P3.
- Handoff notes: Leading and trailing placeholders remain undated, non-statistical, non-persistent, and absent from aggregated accessibility totals. They share a lighter decorative gray than real inactive days, preserving symmetry without implying missed activity. The compact grid, bottom legend, today outline, month markers, Widget kind, App Group, and unrelated `output/` directory are unchanged. Orca desktop capture was unavailable because its runtime was not running, so final pixel-level acceptance remains the user's desktop screenshot.

### TASK-20260811-heatmap-future-week-fill

- Status: Done
- Goal: Preserve the quarterly Widget's compact heatmap layout while drawing inactive-gray placeholders for the not-yet-arrived weekdays after today through the end of the current calendar week, matching the clarified flomo-style visual intent.
- Impacted areas: Internal heatmap cell state, quarterly Widget rendering, packaged-install Widget process lifecycle, focused presentation/packaging regression coverage, README, and project context.
- Verification: Focused `HeatmapPresentationTests` passed 14/14, focused `WidgetSnapshotTests` passed 16/16, focused `PackagingContractTests` passed 25/25, and the final full suite passed 252/252. `bash -n Scripts/build_app.sh` and `git diff --check` passed. The signed `0.2.7 (12)` App/Widget build installed successfully with TeamIdentifier `973KFG9CL9` and the required App Group; App and Widget versions match, PlugInKit resolves exactly one canonical `/Applications` extension, and a new Widget process launched after installation. Two independent final reviews found no remaining P0-P3.
- Handoff notes: Future placeholders do not enter the rolling 90-day date set, activity totals, active/completed days, streaks, month markers, persistence, or per-day accessibility nodes. Leading range padding stays transparent. The earlier adaptive-spacing and title-row legend experiment was removed after the user clarified that the desired fill was future calendar cells rather than redistributed whitespace. The local signed-install lifecycle fix remains because it addresses the independently confirmed stale Widget process that caused an installed build to keep rendering old code; its guarantee does not extend to DMG drag replacement or Sparkle without separate acceptance. Final visual confirmation remains the user's screenshot because local desktop capture was unavailable.

### TASK-20260803-retire-annual-widget

- Status: Done
- Goal: Remove the annual Widget from registration and refresh behavior while preserving the quarterly Widget identity and stored App Group data.
- Impacted areas: Widget bundle registration, Widget kind compatibility contract, quarterly-only layout, README, project context, and regression coverage.
- Verification: `swift test --disable-sandbox` passed 248/248; the focused packaging suite passed 23/23 and the final focused Widget suite passed 16/16. The signed packaged App/Widget build completed with `** BUILD SUCCEEDED **` and verified TeamIdentifier `973KFG9CL9` plus the required App Group. Source and bundle inspection confirmed that only `SitRightQuarterActivityWidget` is configured, while the retired annual string remains only as a reserved compatibility identity. Behavior-level fixtures covered duplicate physical paths, space/tab-delimited output, late-arriving duplicates, consecutive stable observations, missing-parent path traversal, and symlink-plus-parent-traversal rejection. The installed App and Widget both report `0.2.5 (10)`, strict signing passed, and a delayed `pluginkit -A -D` recheck resolved exactly one extension at the canonical Applications location. No discoverable `build/SitRight.app` or pending installation transaction remained. `git diff --check` passed. Two independent compatibility reviews completed; the confirmed identity-reuse, duplicate-registration visibility, output parsing, transient-registration, rollback, path-normalization, registration-stability, and source-isolation gaps were fixed with regression coverage.
- Handoff notes: `SitRightQuarterActivityWidget` remains stable, large-only, and registered. `SitRightActivityWidget` is reserved as a retired identity, is not registered or reloaded, and a regression gate prevents its future reuse. WidgetKit cannot migrate an existing annual placement to the quarterly kind, so affected users must remove the unavailable annual card and add the quarterly card manually. App Group files, activity history, WidgetSnapshot encoding, and entitlements were not changed. After user approval, the candidate version was advanced to `0.2.5 (10)` and installed. Installation now isolates the build source under a non-App suffix, removes every noncanonical physical registration, requires three consecutive observations of the canonical extension, and consumes the discoverable build copy only after a recoverable transaction. Ordinary builds mark `build/` as excluded from metadata indexing and deregister transient products. WidgetKit services were refreshed; final visual confirmation in the reopened component gallery remains a user smoke check because desktop inspection automation was unavailable.

### TASK-20260803-heatmap-goal-progress

- Status: Done
- Goal: Make the quarterly and annual Widget heatmaps communicate daily-goal progress and calendar context without changing Widget identities or persisted activity data.
- Impacted areas: Internal heatmap presentation model, quarterly/annual Widget layout, date-state semantics, accessibility summary, README, project context, and focused regression coverage.
- Verification: `swift test --disable-sandbox` passed 247/247; the signed packaged App/Widget build completed with `** BUILD SUCCEEDED **` and verified TeamIdentifier `973KFG9CL9` plus the required App Group; `git diff --check` passed. Production-view previews covered quarterly large, annual large, and annual medium layouts. Two independent adversarial reviews drove fixes for midnight rollover, annual and non-Gregorian month limits, month-label collision and clipping, quarterly same-week residual months, daylight-saving date ranges, today-outline contrast, and documentation precision; final re-review found no remaining P0-P3.
- Handoff notes: Heatmap color now represents known daily-target completion, with conservative low intensity for trusted legacy activity whose historical target is unknown. Large Widgets add calendar axes and legends; annual medium remains compact. Preserve rolling 90/365-day ranges, stable Widget kinds, the existing trusted-activity count, App Group files, and all unrelated user work. This change intentionally does not add a first-tracked date, so pre-install and unknown inactive history remain visually identical. The packaged Widget was built but not installed over the user's active app; final desktop Widget appearance remains a short user smoke check.

### TASK-20260729-settings-window-hide-switcher

- Status: Done
- Goal: Preserve standard macOS Hide semantics so Command-H keeps SitRight available in Command-Tab while closing the last standard window returns it to menu-bar-only mode.
- Impacted areas: Settings activation lifecycle, status-item reopening, App/Sparkle window close ordering, focused AppKit tests, README, and project context.
- Verification: Focused activation/update tests passed 23/23; `swift test --disable-sandbox` passed 231/231; the signed packaged App/Widget build completed with `** BUILD SUCCEEDED **` and verified TeamIdentifier `973KFG9CL9` plus the required App Group; `git diff --check` passed. Two independent adversarial reviews found and drove fixes for stale asynchronous focus, repeated-registration focus stealing, hidden multiwindow tracking, Sparkle window handoff, and modal alerts that finish without `willClose`; every confirmed issue received regression coverage and final re-review found no remaining P0-P3.
- Handoff notes: Command-H keeps the activation policy regular so the hidden Settings window remains recoverable through Command-Tab or the status item. Closing the last standard Settings/update/modal window restores accessory mode; reminder and status panels do not retain a Dock presence. The signed candidate was built without installation, but desktop automation could not attach to the LSUIElement app before a standard window was opened, so the final visible Command-H → Command-Tab interaction remains a short user smoke check. No settings, reminder, App Group, Widget, update, or version contract changed.

### TASK-20260729-settings-window-menu-activation

- Status: Done
- Goal: Make General and About fit the default Settings window, support native vertical-only resizing, and expose the standard macOS application menu and Command-H while Settings is visible.
- Impacted areas: Settings sizing/restoration, App activation policy, status-menu-to-Settings presentation, native application commands, README, project context, and focused AppKit tests.
- Verification: The focused 41-test presentation/activation run and full 221-test Swift suite passed. The signed packaged App/Widget build completed and verified the required TeamIdentifier and App Group. Runtime acceptance confirmed a fixed 520 pt width, vertical resizing with visible-screen clamping, the standard application/Edit/View/Window/Help menus and system Hide command, and continued status-item process lifetime. The original hide policy incorrectly removed the app from Command-Tab and is superseded by TASK-20260729-settings-window-hide-switcher. Two independent adversarial reviews found and drove fixes for small-screen restoration, screen changes, legacy-size classification, minimum-height recovery, Sparkle-window close ordering, and bounded activation-policy retry; all confirmed findings received regression coverage and final re-review.
- Handoff notes: The resting app remains LSUIElement/accessory with no Dock icon. Settings targets a 520×900 content size, clamps to the current screen, preserves non-legacy user heights, and keeps native scrolling below the full-content height. The candidate was run without replacing the installed app; stored settings, activity history, App Group data, Widget kinds, and version were not changed.

### TASK-20260728-community-quality-release

- Status: Done
- Goal: Complete SitRight's public community, privacy, security, update-status, login-item recovery, and 0.2.3 community-preview release contract without rewriting existing public history.
- Impacted areas: About settings, ServiceManagement and Sparkle presentation, community health files, public-document privacy, release scripts, personal release Skill, tests, README, and GitHub repository settings.
- Verification: The exact merged main candidate passed the isolated Swift suite, signed App/Widget/DMG/update-asset verification, public Feed and asset comparison, and a real current-account in-app update from 0.2.2 (7) to 0.2.3 (8). Repository community/security settings and two independent final reviews passed without a rollback condition.
- Handoff notes: The public build remains a GitHub community preview rather than a Developer ID notarized release. Preserve App Group and stored data formats, and keep personal runtime evidence out of tracked documentation.

### TASK-20260725-proactive-activity-cadence

- Status: Done
- Goal: Keep proactive activity as an additional healthy action without normally replacing the existing reminder cadence, while suppressing an immediately redundant reminder inside a 10-minute protection window.
- Impacted areas: ReminderEngine cadence and guide completion rules, runtime checkpoint recovery, menu/accessibility feedback, Widget snapshot timing, README, and regression coverage.
- Verification: Deterministic cadence and completion-window acceptance passed, including actual-deadline `>`/`=`/`<` 10-minute boundaries, schedule crossing, cancellation, overdue cooldown, lock/sleep, restart, notification failure, no-channel delivery, Widget snapshots, and completion-panel lifecycle. `ReminderEngineTests` passed 42/42; `swift test --disable-sandbox` passed 183/183; `./Scripts/build_app.sh` completed with `** BUILD SUCCEEDED **` and verified the App/Widget TeamIdentifier `973KFG9CL9`; strict signatures, matching App Group entitlements, arm64 binaries, and `git diff --check` passed. Two independent adversarial reviews completed and all confirmed P1/P2 findings were repaired and re-reviewed with no remaining P0-P2.
- Handoff notes: No user setting or AppSettings/history/Widget Codable format changed. Prompted completion starts a fresh interval; proactive completion preserves the actual scheduled reminder unless it is no more than 10 minutes away or cadence is already due. The signed artifact is at `build/SitRight.app` and was not installed over the user's live app or used to mutate live App Group activity history.

### TASK-20260725-resizable-settings-window

- Status: Done
- Goal: Rename the General settings pane to 通用, show the normal settings content without default scrolling, and allow the standard Settings window to resize in both dimensions.
- Impacted areas: Settings Scene sizing/restoration, Settings panel layout and labels, route compatibility, accessibility fallback scrolling, and focused presentation tests.
- Verification: Production Settings hosting and presentation regressions cover the `520×800` default, `460×520` minimum, flexible resizing, visible `通用` title, legacy `schedule` routing, one-time Work Schedule focus, scrolling fallback, and shared tab-window sizing. The combined community-release verification runs the full Swift suite and signed packaged build.
- Handoff notes: This historical sizing policy was superseded by TASK-20260729-settings-window-menu-activation. The `general` and legacy `schedule` raw values, existing AppStorage keys, one-time Work Schedule scroll/focus route, immediate persistence, and accessibility scrolling remain compatible.

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

### TASK-20260727-open-source-community

- Status: Done
- Goal: Add an explicit MIT license and complete the About pane's source, Star, feature-request, bug-report, and third-party-license community entry points without introducing diagnostic collection or upload.
- Impacted areas: About settings presentation, bundled legal notices, GitHub Issue forms, README, project context, packaging resources, and regression coverage.
- Verification: `swift test --disable-sandbox` passed 207/207; `./Scripts/build_app.sh` completed with `** BUILD SUCCEEDED **`. The final arm64 App and Widget passed strict signature validation with TeamIdentifier `973KFG9CL9`, exact App Group entitlements, and no `get-task-allow`. MIT and complete Sparkle 2.9.2 third-party notices are byte-identical between reviewed sources and the packaged App; plist/YAML parsing, shell syntax, secret/conflict scans, and `git diff --check` passed. Production Hosting tests cover the About pane and nonzero legal sheets. Two independent adversarial reviews completed; privacy wording, third-party notice integrity, pre-replacement resource validation, and exact remote-main Git blob gates were repaired and re-reviewed with no remaining P0-P2.
- Handoff notes: Preserve the unrelated untracked `Marketing/` directory. SitRight's MIT text applies to SitRight-owned source; Sparkle 2.9.2 notices remain separate and bundled. Error/crash-log UI is intentionally deferred until a privacy-bounded diagnostic design exists. The next public Release intentionally fails closed until `LICENSE` and both Issue Forms on remote `main` exactly match the verified release commit. Real VoiceOver order, Tab focus, external-link opening, and Esc dismissal remain manual desktop acceptance items.

### TASK-20260727-github-community-updates

- Status: Done
- Goal: Add a Sparkle 2.9.2 GitHub community-preview update path with daily gentle checks, an About settings pane, verified local release assets, and a confirmation-gated GitHub Release step.
- Impacted areas: App lifecycle and menu/settings presentation, Sparkle dependency and sandbox services, nested signing, DMG staging, local appcast/ZIP publication scripts, README, and security/compatibility regression coverage.
- Verification: Script syntax, plist lint, and `git diff --check` passed; `swift test --disable-sandbox` passed 198/198, including short-sleep guide-deadline synchronization before and after the menu popover closes, interrupted Draft-to-public recovery, and rejection of recovery state that does not match the current manifest and remote tag. Signed App/DMG validation covered nested Sparkle/App/Widget signatures, exact sandbox/App Group/Mach entitlements, the required TeamIdentifier, arm64 architecture, and a two-entry read-only DMG. Release tools and immutable assets were pinned and independently reverified without copying private keys or asset hashes into this task board. Publication confirmation/authentication gates were exercised without changing GitHub. Independent adversarial reviews found release atomicity, target-repository, revalidation, key-backup, immutable-candidate/Release Notes/source-build TOCTOU, actual-latest selection, final-App security-setting, update-status, mutable release-tool input, public-transition recovery, recovery-state authorization, and guide deadline issues; all confirmed findings were repaired with focused regression coverage.
- Handoff notes: `0.2.2 (7)` / `v0.2.2` is the designated first update-enabled community preview. It remains a manual-install bootstrap; a real lower-to-higher replacement/relaunch test requires a later build. Publication must use the confirmation-gated local scripts, a restore-tested offline Sparkle-key backup, and the system-keyring `gh` environment. Preserve activity/settings/Widget storage formats and all unrelated `Marketing/` work.

### TASK-20260725-guide-window-content

- Status: Done
- Goal: Prevent the activity guide panel from collapsing to an empty title bar when a manually sized SwiftUI hosting controller is attached.
- Impacted areas: Reminder panel construction, controlled AppKit/SwiftUI sizing, action/close lifecycle, and focused presentation regression coverage.
- Verification: Focused guide/presentation/engine tests passed 11/11; `swift test --disable-sandbox` passed 157/157; `./Scripts/build_app.sh` completed with `** BUILD SUCCEEDED **`, produced and installed an App/Widget pair with TeamIdentifier `973KFG9CL9`, and the installed App was relaunched from `/Applications/SitRight.app`; `git diff --check` passed. An isolated production-source UI smoke rendered the guide at 420×300 with the icon, title, body, live countdown, and cancel action visible. Two independent adversarial reviews completed; the confirmed single-callback/window-cleanup and natural countdown-tick coverage gaps were repaired and re-reviewed with no remaining P0-P3.
- Handoff notes: Keep automatic hosting sizing disabled. `ReminderPanelFactory` must attach the hosting controller before reapplying the measured content size, and `ReminderPresenter` must consume each completion once before closing its panel. The installed status-menu-to-guide interaction was not completed because the local Computer Use runtime was unavailable and the transient popover was not exposed as an accessibility window; avoid claiming that specific interactive path passed without a user-visible smoke check.

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
- Verification: `swift test` passed 121/121, `bash -n Scripts/build_app.sh` and `git diff --check` passed, and the signed build/install completed. Both installed binaries strictly verified against the Apple Development chain, used the required TeamIdentifier and App Group, and had no debugging entitlement. App Group access, shared-snapshot refresh, annual/quarterly Widget timelines, install rollback, registration postconditions, and documentation were independently verified without retaining personal activity values in this public task board.
- Handoff notes: The repaired packaged App was verified as the only active main process selected by PlugInKit. LaunchServices may retain inactive development registrations, so checks should resolve the actual path rather than assume a bundle ID is unique. Build and recovery copies remain local-only. The build script rejects installation unless the App and Widget have the required TeamIdentifier, stages and verifies candidates, and restores the prior App on post-replacement failure.

### TASK-20260723-widget-history-display-recovery

- Status: Done
- Goal: Recover the existing SitRight activity information after the new quarterly widget appeared empty.
- Impacted areas: Installed-app process identity, App Group activity history, Widget snapshot/timeline cache, and recovery backup.
- Verification: The App Group primary history and its recovery copy were decoded with production shared models, compared for continuity, and used to rebuild both annual and quarterly Widget timelines. Duplicate development processes and plug-in registrations were removed without replacing the live history payload. Exact personal dates, counts, hashes, and recovery paths remain in local recovery evidence rather than this public task board.
- Handoff notes: No history payload was replaced. Keep one installed main process active when checking packaged Widget behavior, and never restore a recovery snapshot over newer live history without comparing the local evidence first.

### TASK-20260722-quarter-widget

- Status: Done
- Goal: Add a separate large SitRight widget for the rolling last 90 days while preserving the existing annual widget identity and behavior.
- Impacted areas: Shared Widget kinds and reloads, WidgetKit registration and heatmap presentation, regression coverage, README, project context, and the shared App/Widget build number.
- Verification: `swift test` passed 120/120; `./Scripts/build_app.sh` completed with `** BUILD SUCCEEDED **`; strict App/Widget codesign, arm64 architecture, matching App Group entitlements, packaged binary kind strings, installed-build equality, and system plug-in registration passed. After installing build 6 and restarting Widget services, `chronod` reported two descriptors: the large-only `SitRightQuarterActivityWidget` and medium/large `SitRightActivityWidget`. Two independent adversarial reviews completed and the confirmed documentation findings were repaired.
- Handoff notes: `SitRightActivityWidget` remains stable for existing annual widgets; `SitRightQuarterActivityWidget` is large-only and shares the existing snapshot/history formats. The signed App/Widget pair was installed and verified; recovery evidence was retained only in local, ignored storage.

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
