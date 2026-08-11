# Craft Tasks — web

Mobile-first PWA that mirrors the native macOS app: same Craft task data, same filters/saved views/dashboards, same monochrome dark look. Built for installing on iOS as a home-screen app (Safari → Share → Add to Home Screen) — the Mac app already covers desktop, so this targets the phone.

Live at **https://aviseksengupta.github.io/craft-tasks-web/**

## Develop

```bash
npm install
npm run dev
```

## Deploy

```bash
npm run deploy
```

Builds and pushes `dist/` to the `main` branch of the public [`craft-tasks-web`](https://github.com/aviseksengupta/craft-tasks-web) repo (a separate repo purely for GitHub Pages hosting, since Pages isn't available on this private repo's plan). Pages serves straight from that branch.

## Architecture

- `src/craft.ts` — talks to the same Craft link API as the Swift app (`GET/PUT/POST /tasks`, `GET/DELETE/POST /blocks` for descriptions). Task hashing uses Web Crypto (`SHA-256`) to match the native app's change-detection scheme.
- `src/types.ts` — task model, tag/title parsing from markdown, filter model, date-scope matching — ported 1:1 from `Models.swift`.
- `src/store.tsx` — React context holding tasks, filters, dashboards, sync state. Tasks and the outbox persist to `localStorage`; a 5-minute timer plus an `online` listener re-sync, mirroring `Store.swift`'s `Timer` + offline-outbox design. Edits/creates apply optimistically, queue in `localStorage`, and flush before every sync — Craft being unreachable never blocks the UI.
- `src/gist.ts` — saved views, dashboards, pinned items, and display-name overrides sync to a private GitHub Gist (`craft-tasks-config.json`) when a PAT is set in Settings, so they follow you across devices; without a token they just stay in `localStorage`, matching the Mac app's local-only `filters.json`.
- `src/Sidebar.tsx` / `src/BottomNav.tsx` — two different nav surfaces for the same actions: a full desktop sidebar, and on mobile a bottom tab bar (Home/Tasks/Today/Docs/Menu) with the sidebar becoming a full-screen "Menu" overlay instead of a narrow drawer.
- `src/TaskList.tsx`, `src/Cards.tsx`, `src/DashboardView.tsx` — filter bar + grouped/kanban task list, Documents/Views card grids, and the resizable skyline-packed dashboard grid (same packing algorithm as `DashboardGridLayout` in `Views.swift`).
- `src/styles.css` — the Mac app's warm-charcoal palette as CSS variables, plus a `max-width: 760px` block that swaps in native-feeling mobile chrome: bottom-sheet modals, a floating "+" button, larger tap targets, and `env(safe-area-inset-*)` padding for the iOS notch/home indicator.
- `vite.config.ts` — `vite-plugin-pwa` in `generateSW` mode precaches the app shell (JS/CSS/HTML/icons) for offline load; Craft/GitHub API calls are never cached, since task data already has its own `localStorage` cache and outbox.

## Settings

First launch asks for two things, both stored only in the browser (`localStorage`), never in source:

- **Craft link API URL** — required. The same `https://connect.craft.do/links/…/api/v1` link the Mac app uses.
- **GitHub token** — optional, needs the `gist` scope. Enables cross-device sync of saved views/dashboards via a private Gist. Without it, configs stay local to that browser/device.

## Known limitation

Craft's link API occasionally drops its CORS header or times out on individual requests (observed independently of this app, via `curl`). The app already treats this as a transient error — it shows "Failed to fetch" in the sync status, retries automatically every 5 minutes, and retries immediately on the next manual sync or edit — the same retry posture `SyncEngine.swift` uses for `isLikelyTransient` errors.
