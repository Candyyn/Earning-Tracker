# Android privacy and data safety

LiveTracker stores shifts, breaks, pay periods, and display preferences locally. Android Auto Backup/device transfer includes this data; cloud backup requires encrypted backup support.

Calendar access is optional and requested only after explicit user action. When enabled, LiveTracker reads and writes events in the selected writable calendar for the previous, current, and next month. Stable `livetracker://shift/<id>` metadata identifies app-owned events. Disconnecting stops synchronization but does not remove existing calendar events.

Calendar provider IDs are device-specific. A non-backed-up device binding detects restore/device transfer, clears only stale provider links, and disables calendar sync; shifts and pay data remain intact until the user reconnects.

The app has no analytics, advertising, account, backend, Internet permission, or network data transfer. Release code must not log earnings, rates, shifts, or calendar content.

Google Play Data safety declaration: no data collected or shared; calendar and financial/work data are processed on-device. Backup by Google/Android is controlled by the user's device backup settings.
