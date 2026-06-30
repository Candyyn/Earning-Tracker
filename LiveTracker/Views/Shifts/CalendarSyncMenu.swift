import SwiftUI

struct CalendarSyncMenu: View {
    var viewModel: EarningsViewModel
    var editor: ShiftEditorViewModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var calendarSync = viewModel.calendarSync
        Menu {
            switch calendarSync.state {
            case .disconnected:
                Button("Anslut kalender", systemImage: "calendar.badge.plus") {
                    Task { await editor.connectCalendar() }
                }
            case .denied:
                Button("Öppna Inställningar", systemImage: "gear") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                }
            case .connected, .failed:
                Button("Synka nu", systemImage: "arrow.trianglehead.2.clockwise.rotate.90") {
                    Task { await editor.synchronizeCalendarIfEnabled() }
                }
                Button("Koppla från", systemImage: "calendar.badge.minus", role: .destructive) {
                    calendarSync.disconnect()
                }
            case .syncing:
                Text("Synkar...")
            }
        } label: {
            if calendarSync.state == .syncing {
                ProgressView()
            } else {
                Image(systemName: calendarSync.state.systemImage)
            }
        }
        .accessibilityLabel("Kalendersynk: \(calendarSync.state.title)")
    }
}
