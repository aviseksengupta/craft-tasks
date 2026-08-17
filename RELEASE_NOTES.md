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
