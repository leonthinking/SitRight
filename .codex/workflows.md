# SitRight Agent Workflows

Use this file to keep Codex work repeatable across implementation, debugging, verification, and handoff.

## 1. Intake

Start every task with a short read-only pass.

Recommended commands:

```bash
git status --short
rg --files
```

Then inspect only the files relevant to the task. Prefer `rg` for text search.

Before editing, identify:

- Whether the task touches app logic, UI, Widget, shared storage, packaging, or documentation only.
- Whether generated artifacts would be affected.
- Which verification command is required.
- Whether `.codex/tasks.md` needs a task entry or status update.

## 2. Implementation

General rules:

- Keep edits small and aligned with existing file ownership.
- Preserve unrelated local changes.
- Prefer the existing service/model/view boundaries.
- Use `Sources/Shared` only for types needed by both the app and widget.
- Do not introduce new dependencies, scripts, CI, Makefile, or Justfile unless requested.
- Do not edit `SitRight.xcodeproj`, `.build`, `build`, or `DerivedData`.

When adding or changing settings:

- Update `AppSettings`.
- Preserve default-tolerant decoding.
- Extend `normalized()` if the value is user-controlled.
- Add or update settings tests.
- Check whether the setting should affect `hasReminderScheduleChange(comparedTo:)`.

When changing reminder behavior:

- Inspect `ReminderEngine` and `SchedulePolicy`.
- Preserve `ReminderSessionStateStore` compatibility for pause/resume changes.
- Add tests where behavior can be isolated.
- Verify that widget snapshots still represent the new state correctly.

When changing Widget behavior:

- Inspect `Sources/Shared`, `Widget/`, `WidgetSyncController`, and entitlements.
- Keep App and Widget Codable types compatible.
- Preserve backup recovery and both in-process/cross-process locking for activity-history writes.
- Do not add a packaged-runtime fallback that lets App and Widget write separate Application Support directories.
- Run the packaged build flow when possible.

## 3. Verification Matrix

Use the narrowest command that proves the change.

```bash
swift run
swift test
./Scripts/build_app.sh
```

- Documentation only: run `git status --short` and targeted `rg` checks.
- Model, formatting, persistence, and non-UI logic: run `swift test`.
- App UI changes with no shared or packaged behavior: run `swift test` if logic changed; otherwise compile with the most relevant available command.
- Widget, AppIntent, entitlements, bundle ids, App Group, XcodeGen, app icon, signing, or packaged-app behavior: run `./Scripts/build_app.sh`.
- Launch-at-login changes: validate with packaged app assumptions and document any manual verification requirement.

If verification fails:

- Keep the exact failing command available for handoff.
- Diagnose before changing unrelated code.
- If a tool is missing, report the missing dependency and the skipped verification.

## 4. Handoff

Final handoff should include:

- What changed.
- Files changed.
- Verification commands run and results.
- Any skipped verification with a concrete reason.
- Any known follow-up task that should be added to `.codex/tasks.md`.

Do not claim a command passed unless it was run in the current turn.

## 5. Task Board Usage

Use `.codex/tasks.md` for work that is multi-step, deferred, or useful to preserve between agents.

Each task should record:

- Goal.
- Current status.
- Impacted areas.
- Planned or completed verification.
- Handoff notes.

For a one-turn trivial fix, updating the task board is optional unless the user asked for project tracking.
