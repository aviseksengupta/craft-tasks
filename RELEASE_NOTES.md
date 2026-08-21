# Craft Tasks — Unified Task Screens

## ✨ New Task and Edit Task now behave the same

The New Task and Task Details screens were inconsistent — mentions,
tags, and descriptions worked differently (or not at all) depending on
which one you had open. Both are now the same form with the same
inputs, on both the PWA and the macOS app.

### Features

**Both PWA and macOS app**
- `@document` and `#tag` live autocomplete now works identically whether
  you're creating a new task or editing an existing one
- New: `@<date>` autocomplete sets the **Scheduled** date (not the
  deadline) — type `@today`, `@tomorrow`, `@monday`, `@15`, `@3/15`, or
  `@2026-03-15` and pick the suggestion, Craft-style
- New Task now has a **Description** field, matching Task Details —
  it's saved to Craft as soon as the task itself finishes creating
- Task Details' separate "add tag" box is gone; typing `#tag` inline in
  the task field does the same thing New Task already did

### Installation

**macOS:**
1. Download `CraftTasks.app` (or build with `./build_app.sh`)
2. Drag `Craft Tasks` to Applications folder
3. Launch from Applications (unsigned — "Allow anyway" on first launch)

**PWA (Web):**
- Deployed via `npm run deploy` in `web/` — visit the deployed app URL,
  no action needed

### Requirements

- **macOS:** 11.0 or later (Big Sur+)
- **Web:** Modern browser with localStorage support

---

**Build Date:** 2026-08-21
**Commit:** 2f0b637
**Architecture:** arm64 (Apple Silicon)

---

# Craft Tasks v1.0 Release

## 🎨 New Feature: Tag Colors

Assign custom colors to tags for visual organization. Tasks with colored tags display a 4px left border in the assigned color.

### Features

**PWA (Web App)**
- Color picker in Settings → Tag Colors section
- Add colors for existing tags or create new tag-color associations
- Colors sync across devices via GitHub Gist
- Colored left borders appear on all task cards in lists and detail views

**macOS App**
- Tag Colors settings accessible via paintbrush icon in sidebar
- Predefined 8-color palette for quick selection
- Color assignments persist locally and sync via backup/restore
- Colored left borders on all task views

### Installation

**macOS:**
1. Download `CraftTasks-1.0.dmg`
2. Double-click to mount the DMG
3. Drag `Craft Tasks` to Applications folder
4. Launch from Applications

**PWA (Web):**
- Visit the deployed web app URL
- Colors are managed in Settings → Tag Colors

### Configuration

**Assigning Colors:**
1. Open Settings (gear icon)
2. Scroll to "Tag Colors" section
3. Select a tag and choose a color from the picker
4. Color applies immediately to all tasks with that tag

**Color Palette:**
- Red, Green, Blue, Purple, Gold, Orange, Turquoise, Hot Pink

### Requirements

- **macOS:** 11.0 or later (Big Sur+)
- **Web:** Modern browser with localStorage support

### Known Limitations

- App is unsigned (requires "Allow anyway" on first launch on some Macs)
- Colors are stored as hex strings in config
- PWA colors sync only if GitHub Gist integration is enabled

### Bug Reports & Feedback

Create an issue on GitHub or contact support with:
- Reproduction steps
- Expected vs actual behavior
- Screenshots if applicable

---

**Build Date:** 2024-08-17  
**Commit:** Tag color feature implementation  
**Architecture:** arm64 (Apple Silicon)
