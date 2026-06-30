import SwiftUI

struct TaxRefundView: View {
    @State private var viewModel: TaxRefundViewModel

    init(earningsViewModel: EarningsViewModel) {
        _viewModel = State(initialValue: TaxRefundViewModel(earningsViewModel: earningsViewModel))
    }

    var body: some View {
        Form {
            Section {
                Picker("Inkomstår", selection: $viewModel.selectedIncomeYear) {
                    ForEach(viewModel.availableIncomeYears, id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
                .onChange(of: viewModel.selectedIncomeYear) { _, _ in
                    viewModel.load()
                }
            } footer: {
                Text("Skatteåterbäring betalas normalt ut året efter inkomståret.")
            }

            if let forecast = viewModel.forecast {
                resultSection(forecast)
                trackedDataSection(forecast)
                payoutSection(forecast)
                assumptionsSection
            } else {
                Section {
                    ContentUnavailableView(
                        "Inga inkomster att uppskatta",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("Lägg till pass under \(viewModel.selectedIncomeYear) för att skapa en uppskattning.")
                    )
                }
            }
        }
        .accessibilityIdentifier("taxRefund.list")
        .navigationTitle("Skatteåterbäring")
        .navigationBarTitleDisplayMode(.inline)
        .task { viewModel.load() }
        .alert("Skatteproblem", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func resultSection(_ forecast: TaxRefundForecast) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label(
                    forecast.midpointBalance >= 0 ? "Möjlig återbäring" : "Möjlig kvarskatt",
                    systemImage: forecast.midpointBalance >= 0 ? "arrow.down.circle" : "exclamationmark.triangle"
                )
                .font(.headline)
                .foregroundStyle(forecast.midpointBalance >= 0 ? .green : .orange)

                Text(balanceRange(forecast.estimatedBalance))
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .contentTransition(.numericText())
                    .privacySensitive()

                Label(forecast.confidence.rawValue, systemImage: "gauge.with.dots.needle.33percent")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        } header: {
            Text("Uppskattning")
        } footer: {
            Text("Det här är en grov prognos från LiveTracker-data, inte ett skattebesked från Skatteverket.")
        }
    }

    private func trackedDataSection(_ forecast: TaxRefundForecast) -> some View {
        Section("Spårade data") {
            LabeledContent("Månader med pass", value: "\(forecast.trackedMonthCount) av 12")
            LabeledContent("Bruttolön") {
                Text(SwedishMarket.currencyWithOre(forecast.earnings.grossPay))
                    .privacySensitive()
            }
            LabeledContent("Semesterersättning") {
                Text(SwedishMarket.currencyWithOre(forecast.earnings.vacationPay))
                    .privacySensitive()
            }
            LabeledContent("Uppskattad dragen skatt") {
                Text(SwedishMarket.currencyWithOre(forecast.earnings.estimatedWithheldTax))
                    .privacySensitive()
            }
            LabeledContent("Uppskattad slutlig skatt") {
                Text(currencyRange(forecast.estimatedFinalTax))
                    .privacySensitive()
            }
        }
    }

    private func payoutSection(_ forecast: TaxRefundForecast) -> some View {
        let payoutYear = forecast.incomeYear + 1
        return Section {
            LabeledContent("Tidigaste period", value: payoutYear == 2026 ? "7-10 april 2026" : "April \(payoutYear)")
            LabeledContent("Normal period", value: payoutYear == 2026 ? "9-12 juni 2026" : "Juni \(payoutYear)")
        } header: {
            Text("Möjlig utbetalning")
        } footer: {
            Text("Utbetalning i april kräver normalt digitalt godkännande utan ändringar före Skatteverkets tidiga tidsfrist. Annars betalas en godkänd deklaration normalt i juni.")
        }
    }

    private var assumptionsSection: some View {
        Section {
            Label("Endast pass sparade i LiveTracker ingår.", systemImage: "calendar")
            Label("Dragen skatt uppskattas från appens löneavdrag på 30 %.", systemImage: "percent")
            Label("Slutlig skatt använder Skatteverket-liknande löneregler med 32-36 % kombinerad lokal skatt.", systemImage: "building.columns")
            Label("Ålder, kommun, kyrkotillhörighet, andra arbetsgivare, förmåner, avdrag och kapitalinkomster ingår inte.", systemImage: "exclamationmark.circle")
        } header: {
            Text("Antaganden")
        }
    }

    private func balanceRange(_ range: ClosedRange<Decimal>) -> String {
        if range.upperBound < 0 {
            return "\(currency(-range.upperBound))-\(currency(-range.lowerBound)) i kvarskatt"
        }
        if range.lowerBound >= 0 {
            return "\(currency(range.lowerBound))-\(currency(range.upperBound))"
        }
        return "Mellan kvarskatt och \(currency(range.upperBound)) tillbaka"
    }

    private func currencyRange(_ range: ClosedRange<Decimal>) -> String {
        "\(currency(range.lowerBound))-\(currency(range.upperBound))"
    }

    private func currency(_ amount: Decimal) -> String {
        SwedishMarket.currency(amount)
    }
}
