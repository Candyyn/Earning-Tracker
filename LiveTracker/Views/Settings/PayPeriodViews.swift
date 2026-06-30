import SwiftUI

struct PayPeriodRow: View {
    let setting: PaySettings
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "banknote")
                .foregroundStyle(.green)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(SwedishMarket.currencyWithOre(setting.hourlyRate))
                    .font(.body.weight(.medium))
                Text(PayPeriodFormatting.range(setting))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if isActive {
                Label("Aktiv", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct PayPeriodDetailView: View {
    @Bindable var viewModel: SettingsViewModel
    let payPeriodID: UUID

    private var setting: PaySettings? {
        viewModel.settings.first(where: { $0.id == payPeriodID })
    }

    var body: some View {
        Form {
            if let setting {
                Section {
                    LabeledContent {
                        TextField("Timlön", value: hourlyRateBinding, format: .currency(code: "SEK").locale(SwedishMarket.locale))
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                    } label: {
                        Label("Timlön", systemImage: "banknote")
                    }
                } header: {
                    Text("Bruttolön")
                } footer: {
                    Text("När bruttolönen ändras räknas alla uppskattade nettobelopp nedan om.")
                }

                Section {
                    DatePicker("Börjar", selection: startDateBinding, displayedComponents: .date)
                    DatePicker("Slutar", selection: endDateBinding, displayedComponents: .date)
                } header: {
                    Text("Giltighetsperiod")
                } footer: {
                    Text("Angränsande perioder justeras automatiskt för att undvika glapp och överlapp.")
                }

                Section {
                    CalculatedRateRow(title: "Dag", detail: "08:00-18:00", systemImage: "sun.max", value: setting.dayRate)
                    CalculatedRateRow(title: "Kväll", detail: "18:00-24:00", systemImage: "sunset", value: setting.eveningRate)
                    CalculatedRateRow(title: "Natt", detail: "00:00-08:00", systemImage: "moon", value: setting.nightRate)
                    CalculatedRateRow(title: "Helg", systemImage: "calendar", value: setting.weekendRate)
                    CalculatedRateRow(title: "Storhelg A", systemImage: "flag", value: setting.holidayRateA)
                    CalculatedRateRow(title: "Storhelg B", systemImage: "star", value: setting.holidayRateB)
                } header: {
                    Text("Uppskattade nettobelopp")
                } footer: {
                    Text("Inkluderar semesterersättning, uppskattad skatt och relevanta OB-tillägg.")
                }
            } else {
                ContentUnavailableView("Löneperioden är inte tillgänglig", systemImage: "banknote")
            }
        }
        .navigationTitle("Löneperiod")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
    }

    private var hourlyRateBinding: Binding<Decimal> {
        Binding(
            get: { setting?.hourlyRate ?? 0 },
            set: { viewModel.updateHourlyRate(for: payPeriodID, to: $0) }
        )
    }

    private var startDateBinding: Binding<Date> {
        Binding(
            get: { setting?.startRange ?? .now },
            set: { viewModel.updateStartDate(for: payPeriodID, to: $0) }
        )
    }

    private var endDateBinding: Binding<Date> {
        Binding(
            get: {
                guard let endRange = setting?.endRange else { return .now }
                return Calendar.current.date(byAdding: .day, value: -1, to: endRange) ?? endRange
            },
            set: { inclusiveEnd in
                let exclusiveEnd = Calendar.current.date(byAdding: .day, value: 1, to: inclusiveEnd) ?? inclusiveEnd
                viewModel.updateEndDate(for: payPeriodID, to: exclusiveEnd)
            }
        )
    }
}

private struct CalculatedRateRow: View {
    let title: String
    var detail: String? = nil
    let systemImage: String
    let value: Decimal

    var body: some View {
        LabeledContent {
            Text(SwedishMarket.currencyWithOre(value))
                .monospacedDigit()
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private enum PayPeriodFormatting {
    static func range(_ setting: PaySettings) -> String {
        let inclusiveEnd = Calendar.current.date(byAdding: .day, value: -1, to: setting.endRange) ?? setting.endRange
        return "\(setting.startRange.formatted(.dateTime.locale(SwedishMarket.locale).day().month(.abbreviated).year())) - \(inclusiveEnd.formatted(.dateTime.locale(SwedishMarket.locale).day().month(.abbreviated).year()))"
    }
}
