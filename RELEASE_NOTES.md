# Craft Tasks — Send tasks to Google Calendar

Craft has no concept of a time-of-day or a reminder on a task, and it never
will here — Craft stays the single source of truth for tasks. Instead, a
**dedicated Google Calendar** becomes a separate store for the handful of
tasks that need to happen at a specific time, and Google's own calendar
notifications (loud, cross-device, hard to miss) do the reminding.

## 📅 "Send to Calendar"

Every open task now has a small calendar button (in the task row and in the
edit sheet). It opens a short dialog:

- **Title** — prefilled from the task, editable
- **Date** — prefilled from the task's scheduled date (or deadline, or
  today), editable
- **Time** — the bit Craft can't hold
- **Repeat** — none / daily / weekly / every weekday / monthly, with an
  optional end date

Confirm, and a single event is created in a calendar called **Craft Tasks**.
That's the whole interaction — a **one-way, one-shot push**. The event is
independent of the task afterwards; there is no background sync.

## 🗓️ Calendar view

A new **Calendar** entry in the menu shows a **weekly agenda** of just the
Craft Tasks calendar — seven days at a time, prev/next week, "Today". Tap any
event to change its title, date, time or repeat, or to delete it (a single
occurrence or the whole series). A "+" on any day adds an ad-hoc event.

## ⚙️ Setup (once)

**Settings → Google Calendar:**

1. Paste a **Google OAuth Client ID** (a Web client from Google Cloud
   Console with the Calendar API enabled). The settings screen shows the
   exact origin to add to the client's *Authorized JavaScript origins*.
2. **Connect Google Calendar** and approve (the `calendar` scope). It only
   ever reads or writes the dedicated **Craft Tasks** calendar — it just
   doesn't ask Google to enforce that.

On connect the app looks for an existing **Craft Tasks** calendar before
making one, so signing in from a second device adopts the same calendar
rather than creating a duplicate.

## 📱 Where it works

The PWA (iPhone home screen, desktop browser). Put your Google account in
**iOS Settings → Calendar** (not just the Google Calendar app) so Apple's
Calendar fires the alerts — those are Time Sensitive and break through
Focus, which is the "meeting now" urgency the notifications are for.

The macOS app is unchanged for now; it can get the same button later.
