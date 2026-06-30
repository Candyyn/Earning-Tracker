import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    var earningsViewModel: EarningsViewModel

    @State private var pendingDeletion: PaySettings?
    @State private var calendarErrorMessage: String?

    var body: some View {
        Form {
            payPeriodsSection
            financialToolsSection
            displaySection
            calendarSection
        }
        .accessibilityIdentifier("settings.list")
        .navigationTitle("Inställningar")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            earningsViewModel.calendarSync.refreshAuthorizationState()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            earningsViewModel.calendarSync.refreshAuthorizationState()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.createPayPeriod()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Lägg till löneperiod")
                .accessibilityIdentifier("settings.addPayPeriod")
            }
        }
        .confirmationDialog(
            "Ta bort löneperiod?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { setting in
            Button("Ta bort löneperiod", role: .destructive) {
                viewModel.deletePayPeriod(id: setting.id)
                pendingDeletion = nil
            }
            Button("Avbryt", role: .cancel) {}
        } message: { setting in
            Text("Angränsande löneperiod förlängs så att lönehistoriken förblir sammanhängande.")
        }
        .alert("Inställningsproblem", isPresented: Binding(
            get: {
                viewModel.persistenceError != nil ||
                viewModel.periodErrorMessage != nil ||
                calendarErrorMessage != nil
            },
            set: { isPresented in
                if !isPresented {
                    viewModel.persistenceError = nil
                    viewModel.periodErrorMessage = nil
                    calendarErrorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                viewModel.persistenceError ??
                viewModel.periodErrorMessage ??
                calendarErrorMessage ?? ""
            )
        }
    }

    private var payPeriodsSection: some View {
        Section {
            ForEach(viewModel.settings.sorted(by: { $0.startRange > $1.startRange })) { setting in
                NavigationLink {
                    PayPeriodDetailView(viewModel: viewModel, payPeriodID: setting.id)
                } label: {
                    PayPeriodRow(setting: setting, isActive: viewModel.paySettings(for: .now)?.id == setting.id)
                }
                .accessibilityIdentifier("settings.payPeriodRow")
                .swipeActions {
                    Button("Ta bort", systemImage: "trash", role: .destructive) {
                        pendingDeletion = setting
                    }
                    .disabled(viewModel.settings.count == 1)
                }
            }
        } header: {
            Text("Löneperioder")
        } footer: {
            Text("Rätt löneperiod väljs automatiskt utifrån när varje pass ligger.")
        }
    }

    private var displaySection: some View {
        Section("Visning") {
            Toggle(isOn: $viewModel.showEarned) {
                Label(
                    "Visa intjänat",
                    systemImage: viewModel.showEarned ? "eye" : "eye.slash"
                )
            }
            .accessibilityHint("Styr om intjänat belopp visas på startsidan.")
        }
    }

    private var financialToolsSection: some View {
        Section("Ekonomiska verktyg") {
            NavigationLink {
                TaxRefundView(earningsViewModel: earningsViewModel)
            } label: {
                Label("Skatteåterbäring", systemImage: "building.columns")
            }
            .accessibilityIdentifier("settings.taxRefund")
        }
    }

    @ViewBuilder
    private var calendarSection: some View {
        @Bindable var calendarSync = earningsViewModel.calendarSync

        Section {
            LabeledContent {
                HStack(spacing: 8) {
                    if calendarSync.state == .syncing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(calendarSync.state.title)
                        .foregroundStyle(.secondary)
                }
            } label: {
                Label("Kalendersynk", systemImage: calendarSync.state.systemImage)
            }

            switch calendarSync.state {
            case .disconnected:
                Button("Anslut kalender", systemImage: "calendar.badge.plus") {
                    connectCalendar()
                }
            case .denied:
                Button("Öppna Inställningar", systemImage: "gear") {
                    openSystemSettings()
                }
            case .connected, .failed:
                Button("Synka nu", systemImage: "arrow.trianglehead.2.clockwise.rotate.90") {
                    synchronizeCalendar()
                }
                Button("Koppla från kalender", systemImage: "calendar.badge.minus", role: .destructive) {
                    calendarSync.disconnect()
                }
            case .syncing:
                EmptyView()
            }
        } header: {
            Text("Kalender")
        } footer: {
            Text("När kalendern är ansluten synkas passen med kalendern Arbetspass på den här enheten.")
        }
    }

    private func connectCalendar() {
        Task {
            do {
                try await earningsViewModel.connectCalendar()
            } catch {
                calendarErrorMessage = error.localizedDescription
            }
        }
    }

    private func synchronizeCalendar() {
        Task {
            do {
                try await earningsViewModel.synchronizeCalendarIfEnabled()
            } catch {
                calendarErrorMessage = error.localizedDescription
            }
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
