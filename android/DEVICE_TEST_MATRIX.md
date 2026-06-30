# Android release validation matrix

Record device model, Android version, calendar provider/version, build SHA, and result for every run. Do not mark parity complete until all required rows pass.

## Automated result — 2026-06-29

- Medium Phone AVD, Android 17/API 37: 22 JVM tests and 13 connected tests passed.
- Room migrations, repositories, calendar grouping/import/update/deletion, UI navigation, editor preset/dirty-state restoration, tax, and earnings-visibility persistence passed.
- `lintDebug` passed.
- Minified/resource-shrunk `assembleRelease` passed.
- Still required on physical hardware: Google Calendar provider, one OEM calendar provider, TalkBack/manual font-scale matrix, and backup/device-transfer exercise.

## Required devices

- Minimum supported API 23 device/emulator.
- Current stable Android device.
- Google Calendar provider.
- One OEM provider (Samsung, Xiaomi, OnePlus, or equivalent).

## Core workflow

- Fresh install creates one continuous default pay period.
- Day/evening/night presets, overnight shifts, paid/unpaid breaks, edit, discard, delete, and undo work.
- Rotation and process recreation preserve selected month; persisted shifts/pay periods remain correct.
- Active earnings update, stop during unpaid break, and recalculate after foreground/timezone/date changes.
- Hidden earnings and secure-recents preferences persist.
- Tax-refund output matches iOS fixtures for sparse and complete years.

## Calendar

- Permission grant, denial, repeat request, revocation, and app-settings recovery show correct states.
- Explicit connect creates/chooses writable `Shifts` calendar; disconnect stops synchronization.
- App shift creates work/break/work events with stable `livetracker://shift/<id>` metadata.
- App edit/delete updates/removes every related event; undo recreates links.
- Calendar-only event imports; provider edits update Room; provider deletion removes synchronized Room shift.
- Duplicate events, stale stored IDs, missing writable calendars, and failed/partial provider batches surface errors without replacing known-good IDs.
- Manual sync is limited to previous/current/next month and produces no duplicates across repeated runs.

## Accessibility and layout

- TalkBack order and labels are correct on dashboard, shifts, editor, settings, tax refund, and permission flows.
- Font scales 1.0, 1.3, and 2.0 show no clipped controls or unreachable actions.
- Light/dark themes, portrait/landscape, split screen, and compact/large phone widths remain usable.
- Interactive controls meet Material minimum touch target and contrast requirements.

## Release and performance

- `testDebugUnitTest`, `connectedDebugAndroidTest`, `lintDebug`, and `assembleRelease` pass.
- No earnings, rates, shift times, or calendar content appear in release logs.
- Cold startup, month navigation, active ticker, and calendar sync show no ANRs or sustained recomposition/CPU spikes.
- Backup/device transfer restores Room and DataStore data, clears device-specific calendar links, preserves shifts, and requires explicit calendar reconnection.
