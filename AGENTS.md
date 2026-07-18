# SitRight Agent Guide

This is the first file Codex agents should read before changing this repository.

## Project Shape

SitRight is a lightweight macOS menu bar posture and break reminder app.

- Language/runtime: Swift 6, macOS 14.
- App form: AppKit `NSStatusItem` + non-animated `NSPopover` hosting SwiftUI content, accessory app, no Dock icon.
- Extension: WidgetKit macOS widget extension.
- Build sources of truth:
  - `Package.swift` defines the SwiftPM executable and tests.
  - `project.yml` defines the generated Xcode project, app target, widget extension, bundle ids, signing defaults, and version settings.
  - `Scripts/build_app.sh` generates and builds the `.app` bundle with the widget extension.

Generated artifacts and local build products must not be edited directly:

- `SitRight.xcodeproj/`
- `.build/`
- `build/`
- `DerivedData/`

If the Xcode project needs to change, update `project.yml`, then regenerate through the existing build flow.

## Directory Map

- `Sources/SitRightApp.swift`: SwiftUI app entry point and application delegate wiring.
- `Sources/StatusBarController.swift`: native status item, persistent SwiftUI hosting, popover lifecycle, and status accessibility wiring.
- `Sources/AppContainer.swift`: dependency assembly for settings, stats, notifications, popup presenter, widget sync, and reminder engine.
- `Sources/Services/`: app services including `ReminderEngine`, persistence stores, notification delivery, launch-at-login, and widget sync.
- `Sources/Models/`: app settings and daily stats model aliases.
- `Sources/Shared/`: types and storage used by both the main app and widget extension.
- `Sources/Views/`: menu bar panel, settings, today view, popup, ring, and status label UI.
- `Widget/`: WidgetKit configuration, timeline provider, and the display-only medium/large widget UI.
- `AppBundle/` and `WidgetBundle/`: Info.plist and entitlement files.
- `Tests/`: focused XCTest coverage for settings, reminder scheduling/state, stats, activity-history recovery/concurrency, time formatting, and widget snapshot behavior.
- `Assets.xcassets/`: app icon assets.
- `.codex/`: agent context, workflows, and task board.

## Required Reading by Task Type

- Any task: read this file first.
- Architecture or behavior changes: also read `.codex/project-context.md`.
- Implementation, debugging, or handoff work: also read `.codex/workflows.md`.
- Multi-step or deferred work: record/update the item in `.codex/tasks.md`.

## Commands

Use existing commands only. Do not add a Makefile, Justfile, CI workflow, or new wrapper script unless the user explicitly asks.

```bash
swift run
swift test
./Scripts/build_app.sh
```

Command selection:

- `swift run`: quick local run of the menu bar app through SwiftPM. This does not validate the packaged WidgetKit extension.
- `swift test`: default verification for business logic, model, formatting, persistence, and shared data changes.
- `./Scripts/build_app.sh`: required verification for changes involving WidgetKit, entitlements, bundle identifiers, App Group access, `project.yml`, app icon assets, signing/package behavior, or launch-at-login packaging assumptions.

## Validation Rules

- Documentation-only changes: `git status --short` plus targeted `rg` checks are sufficient unless the user asks for a full test run.
- Swift business logic changes: run `swift test`.
- UI-only SwiftUI changes: run `swift test` if logic or shared types are touched; otherwise at least confirm the project still compiles through the most relevant available command.
- Widget, entitlement, bundle id, App Group, XcodeGen, packaging, or app-extension changes: run `./Scripts/build_app.sh`.
- If a required command cannot run because a dependency is missing, report the exact blocker and the command that failed.

## High-Risk Areas

Handle these with extra care and explicit verification:

- App Group: `973KFG9CL9.com.leon.SitRight`.
- Bundle identifiers:
  - App: `com.leon.SitRight`.
  - Widget extension: `com.leon.SitRight.SitRightWidgetExtension`.
- Entitlements in `AppBundle/` and `WidgetBundle/`.
- Shared storage in `Sources/Shared/SharedStorage.swift`.
- Runtime pause persistence in `Sources/Services/ReminderSessionStateStore.swift`.
- Widget snapshot and history files:
  - `SitRightWidgetSnapshot.json`
  - `SitRightActivityHistory.json`
- Reminder scheduling state in `ReminderEngine`.
- Settings normalization and persistence compatibility in `AppSettings` and `SettingsStore`.
- Launch-at-login behavior, which depends on running from a packaged `.app`.

## Working Rules

- Preserve unrelated user changes. Check `git status --short` before editing and before finishing.
- Prefer small, scoped edits that follow the existing SwiftUI and service boundaries.
- Do not move business logic into views unless the surrounding code already does so.
- Do not duplicate shared App/Widget types; place cross-target data in `Sources/Shared`.
- Packaged App/Widget code must not silently fall back from the App Group to separate sandbox storage.
- Do not edit generated artifacts or local build products.
- Keep user-facing copy consistent with the current Chinese product language.
- Final handoff should list changed files, verification performed, and any command that could not be run.
