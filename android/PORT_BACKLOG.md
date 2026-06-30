# Android Port Backlog

This document tracks the remaining work required to reproduce the iOS LiveTracker experience with Android-native architecture and interaction patterns. PDF/pay-slip verification is intentionally out of scope.

## Target

- Preserve the iOS app's pay rules, shift behavior, calendar semantics, and visual identity.
- Use Android conventions: Jetpack Compose, Material 3, Room, DataStore, lifecycle-aware state, Android Calendar Provider, and runtime permissions.
- Treat the existing iOS behavior and tests as the product specification where this document does not explicitly define an Android difference.

## Current Android baseline

Implemented baseline now includes the complete native Compose workflow, Room/DataStore persistence, exact iOS-derived earnings and tax rules, pay periods, breaks, live tracking, Calendar Provider synchronization, localization, privacy controls, and release hardening described below.

Progress since the baseline:

- A1 foundation: Room-backed continuous pay periods, exact iOS-derived net rates, schema migration, and transactional split/delete operations.
- A2 implementation complete: exact rate, holiday, clock, and pay-period boundaries with partial-minute and DST-safe `Instant` durations, plus persisted exact dominant-type classification. Full parity matrix remains under A13.
- A3 implementation complete: paid/unpaid break editing, containment validation, safe legacy-break handling, and net duration display. Editor UI tests remain under A13/A14.
- A4–A9 implementation complete: repository/state separation, lifecycle-aware state, native editor pickers and presets, monthly summaries, live tracking, DataStore display/privacy settings, and full pay-period management.
- Tax-refund forecast ported after parity audit found it in the current iOS settings flow.
- A10–A12 implementation complete: opt-in runtime permissions, Android Calendar Provider adapter, stable event metadata, grouped break events, three-month bidirectional sync, deletion handling, and transactional provider mutations.
- A13–A16 implementation complete in source: expanded JVM parity tests, Compose/migration/repository instrumentation tests, English/Swedish resources, accessibility labels, Room migrations, encrypted-backup rules, privacy inventory, adaptive/monochrome icon, and minified release config.
- Automated validation complete on an Android 17 AVD: 22 JVM tests, 13 connected migration/repository/calendar/UI tests, `lintDebug`, and the minified `assembleRelease` build pass. Google Calendar plus one vendor provider still require physical-device verification.

Required manual/device cases are tracked in [DEVICE_TEST_MATRIX.md](DEVICE_TEST_MATRIX.md).

## Milestone 1 — Domain and persistence parity (P0)

### A1. Port pay periods and exact rate calculation

- Replace the single `PaySettings` preference with a Room `PayPeriodEntity`.
- Store ID, gross hourly rate, effective start, and exclusive effective end.
- Calculate the six read-only net rates exactly like `PaySettings.recalculateRates()` on iOS:
  day, evening, night, weekend, holiday A, and holiday B.
- Select the pay period containing each earnings segment, including shifts crossing a pay-period boundary.
- Create a sensible initial period for new installations.
- Preserve continuous periods when creating or deleting a period; prevent gaps and overlaps.
- Add Room migrations for every schema change after this milestone.

Acceptance:

- The same shift and pay-period fixtures produce the same earnings on iOS and Android to the displayed currency precision.
- Creating and deleting adjacent periods preserves a continuous timeline.
- Setting gross pay to zero clears every calculated rate.

### A2. Replace sampled calculations with exact boundaries

Status: implementation complete; full parity test matrix remains under A13.

- Replace the Android calculator's current 15-minute sampling with boundary-based segments.
- Split at 00:00, 08:00, 18:00, holiday start/end, pay-period start/end, shift end, and break boundaries.
- Handle daylight-saving transitions using `ZonedDateTime`/`Instant` deliberately.
- Retain partial-minute accuracy.
- Calculate and persist/display each shift's dominant type using the same precedence as iOS.

Acceptance:

- Exact parity tests cover weekday, evening, night, weekend, holiday A/B, New Year crossing, midnight crossing, DST, and rate-period crossing.
- No loop can stall when a boundary resolves to the current instant.

### A3. Complete break behavior

Status: implementation complete; editor UI tests remain under A13/A14.

- Add break start/end controls to the editor.
- Add paid/unpaid selection.
- Validate that a break is ordered and contained within the shift.
- Treat invalid or reversed legacy break data safely without double-counting.
- Show break information and net worked duration in shift rows/details.

Acceptance:

- Paid breaks count toward hours and earnings; unpaid breaks do not.
- Invalid input cannot be saved and receives inline Material validation.

### A4. Repository and state architecture

Status: implementation complete.

- Introduce repositories for shifts, pay periods, settings, and calendar integration.
- Move business logic out of composables and keep screen state in lifecycle-aware ViewModels.
- Use `Flow` as the database source of truth.
- Add explicit loading, empty, and failure states.
- Ensure changes recalculate the dashboard without restarting the activity.

## Milestone 2 — Shift workflow and UI parity (P0)

### A5. Complete shift editor

Status: implementation complete.

- Replace free-text date/time fields with Material date and time pickers.
- Add Day (08:00–17:00), Evening (16:00–23:00), and Night (22:00–07:00) presets.
- Correctly advance overnight end dates.
- Support editing without changing the shift ID or existing calendar IDs.
- Track dirty state and show a discard confirmation on back/dismiss.
- Show save failures without losing entered values.

### A6. Complete monthly shift screen

Status: implementation complete.

- Group shifts by date.
- Show month totals: earnings, worked hours, and shift count.
- Show the day/evening/night/weekend/holiday A/holiday B hour breakdown.
- Add dominant-type color and icon treatment to each shift.
- Add delete confirmation and undo snackbar where safe.
- Preserve selected month across configuration changes and process recreation.
- Use edge-to-edge layout, system back handling, and adaptive spacing.

### A7. Dashboard live tracking

Status: implementation complete.

- Update earnings while a shift is active without keeping unnecessary work running in the background.
- Show current effective hourly rate and break status.
- Change the aura colors by current shift type and earnings progress.
- Respect the earnings-visibility setting and obscure sensitive content in recents where appropriate.
- Recalculate on shift, pay-period, timezone, date, and locale changes.

Acceptance:

- Foreground tracking updates at the next meaningful rate boundary and at a reasonable display cadence.
- Leaving and returning to the app produces the correct current value immediately.

## Milestone 3 — Settings parity (P0)

### A8. Pay-period management UI

Status: implementation complete.

- List pay periods with effective dates and gross hourly rate.
- Add, edit, and delete periods using Material dialogs/screens.
- Display calculated rates as read-only values with Swedish currency formatting.
- Explain automatic adjustment of adjacent periods.
- Validate ranges and report persistence errors.

### A9. Display and app preferences

Status: implementation complete.

- Port the `showEarned`/hide-earnings preference.
- Identify and port any remaining user-facing iOS defaults that affect behavior.
- Persist preferences with DataStore; keep relational pay data in Room.
- Add a reset/export option only if product requirements call for it.

## Milestone 4 — Android calendar integration (P1)

### A10. Calendar permission and connection state

Status: implementation complete; device permission-flow verification pending.

- Add `READ_CALENDAR` and `WRITE_CALENDAR` permissions.
- Request permissions at the point of use with the Activity Result API.
- Model disconnected, permission-required, connected, syncing, and failed states.
- Require explicit opt-in before any synchronization.
- Provide Android-standard rationale and “Open app settings” recovery.

### A11. Calendar Provider adapter

Status: implementation complete; Google/OEM provider verification pending.

- Use Android's Calendar Provider rather than reproducing EventKit APIs.
- Select a writable account/calendar or create a dedicated “Shifts” calendar when the provider supports it.
- Define stable app metadata for matching events. Do not rely only on mutable titles.
- Represent work-before-break, break, and work-after-break consistently.
- Store provider event IDs without overwriting known-good IDs after a failed save.
- Handle providers that modify, duplicate, or remove events.

### A12. Bidirectional synchronization

Status: implementation and emulator execution complete; physical Google/OEM provider verification pending.

- Import calendar-only shifts from the synchronization window.
- Update app-owned shifts and their related events.
- Delete related events when a synchronized shift is deleted.
- Merge grouped work/break events back into one shift.
- Define conflict behavior when both Room and Calendar changed.
- Limit sync to the iOS-equivalent previous/current/next month window unless product needs differ.
- Run manual sync in the foreground; use WorkManager only if periodic/background sync is later required.

Acceptance:

- Test against Google Calendar and at least one device-vendor calendar provider.
- Denial, revocation, missing writable calendars, partial saves, duplicate events, and provider deletion are covered.

## Milestone 5 — Quality and platform completion (P0 before release)

### A13. Port the iOS behavioral test suite

Status: complete. All 22 JVM parity tests and 13 Android 17 connected migration/repository/calendar/UI tests pass.

- Port all earnings tests, not only the current three.
- Port pay-period continuity and recalculation tests.
- Port shift-editor validation and dirty-state tests.
- Port repository month-change tests.
- Port calendar opt-in and failed-save ID-preservation tests.
- Add Room migration tests and timezone/DST parameterized tests.

### A14. Compose UI and integration tests

Status: complete for automated launch scope. Dashboard/navigation/editor restoration, presets, calendar synchronization, repository, migration, tax, and earnings-visibility persistence tests pass on Android 17.

- Dashboard navigation and earnings visibility.
- Shift creation, preset use, break editing, overnight shift, edit, and delete confirmation.
- Empty-month action and month navigation.
- Pay-period create/edit/delete workflows.
- Calendar permission and connection-state flows using fakes.
- Stable semantic test tags for important controls.

### A15. Accessibility and localization

Status: English/Swedish resources, scalable Compose layout, standard touch targets, and control descriptions implemented. TalkBack/manual font-scale verification pending.

- Add content descriptions and meaningful merged semantics.
- Support font scaling without clipping and touch targets of at least Material minimum size.
- Check TalkBack order and announcements for errors/live values.
- Move every user-facing string into resources.
- Add Swedish and English resources, or explicitly choose one launch language.
- Use locale-aware SEK, date, duration, and decimal formatting.
- Verify light/dark theme and sufficient contrast.

### A16. Android lifecycle, backup, and privacy

Status: implementation complete; minified release artifact passes R8/resource shrinking verification.

- Verify process-death restoration and database durability.
- Define Auto Backup/data extraction rules for shifts and settings.
- Add a privacy policy/data-safety inventory for calendar access and local earnings data.
- Ensure logs never contain earnings, calendar contents, or pay details in release builds.
- Add release R8 configuration and verify the minified build.
- Add proper adaptive launcher icon, monochrome icon, app name, versioning, and release signing configuration.

### A17. Performance and compatibility

Status: bounded monthly calculation, foreground-only ticker, Android 17 execution, lint, and release build complete; minimum-API/physical-device profiling matrix pending.

- Profile startup, Room queries, recomposition, and monthly calculation cost.
- Avoid recomputing all historical shifts on every dashboard tick.
- Test the minimum supported API and the current target API.
- Test phone sizes, landscape, split screen, and at least one physical device.
- Run Android Lint and resolve release-blocking findings.

## Milestone 6 — Optional cross-platform data movement (P2)

There is currently no shared backend. If users must move from iPhone to Android:

- Define a versioned JSON/CSV export containing shifts, breaks, pay periods, and stable UUIDs.
- Add export/import on both platforms using their native document pickers.
- Validate and preview imports before committing them transactionally.
- Document that Calendar event IDs are device/provider-specific and must not migrate.

This is separate from normal Android parity and should only be scheduled if migration is a product requirement.

## Explicitly excluded

- PDF/pay-slip parsing and verification.
- Literal reproduction of iOS sheets, glass materials, SF Symbols, or EventKit behavior where Android has a different standard pattern.
- Background calendar synchronization until foreground/manual synchronization is reliable and a product need for background work is established.

## Recommended execution order

1. A1–A4: make the data model and calculations trustworthy.
2. A5–A9: reach core app UI and settings parity.
3. A13–A15: lock behavior down with tests and accessibility before platform integrations grow.
4. A10–A12: add calendar synchronization behind a tested adapter.
5. A16–A17: release hardening.
6. Milestone 6 only if cross-platform migration is required.

## Definition of Android parity

The Android port is feature-complete when a user can configure date-effective pay, create and manage equivalent shifts and breaks, see the same earnings and monthly breakdown as iOS, explicitly synchronize with an Android calendar, and complete the tested workflows with native Android navigation, permissions, accessibility, and lifecycle behavior.
