# Craft Tasks

Native macOS (SwiftUI) app that mirrors all tasks from your Craft space into a local SQLite database and presents them in a filterable, minimal dark UI.

A mobile-first PWA with the same features and look lives in [`web/`](web/) — install it from Safari on iOS (Share → Add to Home Screen). Live at **https://aviseksengupta.github.io/craft-tasks-web/**.

## Build & run

```bash
./build_app.sh && open "Craft Tasks.app"
```

Requires only Swift command-line tools (no Xcode).

## Architecture

- `Sources/CraftTasks/SyncEngine.swift` — downloads `GET /tasks?scope=all` from the Craft link API, hashes each raw task payload (SHA-256), and diffs against local hashes: new → insert, changed → update, missing → delete. Runs on launch, every 5 minutes, and on ⌘R / the refresh button.
- `Sources/CraftTasks/Database.swift` — SQLite store at `~/Library/Application Support/CraftTasks/tasks.sqlite` (tasks + meta tables).
- `Sources/CraftTasks/Models.swift` — task model, tag extraction from markdown (`#tag`), filter model.
- `Sources/CraftTasks/Store.swift` — observable app state, saved filters persisted to `filters.json`, home-view selection.
- `Sources/CraftTasks/Theme.swift` / `Views.swift` — monochrome dark theme and all UI.
- `Resources/bw-logo-1.png` — app icon source; `build_app.sh` regenerates `AppIcon.icns` from it on every build.

## Features

- **Filters**: any combination of tags (multi-select), documents (multi-select), state (open/done/canceled), date scope (today / overdue / next 7 days / this month / no date), has-deadline, and free-text search.
- **Saved views**: save any filter combination from the header; right-click a saved view in the sidebar to set it as **Home** or delete it.
- **Documents view**: grid of every document that contains tasks, with open/done/overdue counts and a progress bar; click a card to drill into its tasks.
- **Editing**: click any task to open the editor — text/description, inline hashtags (chips to add/remove), state, scheduled date, deadline (both clearable), and which document it lives in (or Inbox) via a picker in the header — changing it moves the task. Edits apply locally at once and push to Craft immediately via `PUT /tasks`; if Craft is unreachable they persist in a SQLite outbox (`pending_updates`) shown as "N change(s) queued" and are flushed before the next sync. Sync never overwrites a task with a queued edit.
