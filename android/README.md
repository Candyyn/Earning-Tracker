# LiveTracker Android

Native Kotlin app using Jetpack Compose and Room.

Implemented: live earnings dashboard, Room-backed native shift workflow, exact Swedish rate/holiday calculations, continuous pay periods, tax-refund forecast, DataStore preferences, English/Swedish UI, and opt-in Android Calendar Provider synchronization. PDF verification is intentionally excluded.

Remaining release gates: connected instrumentation tests, TalkBack/font-scale checks, and Google Calendar plus one OEM provider verification.

See [PORT_BACKLOG.md](PORT_BACKLOG.md) for the complete parity plan and acceptance criteria.

Open this directory in Android Studio, install Android SDK 36 when prompted, select JDK 17, and run `app`.
