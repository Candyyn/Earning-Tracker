import SwiftUI
import UniformTypeIdentifiers

struct PaySlipVerificationView: View {
    var earningsViewModel: EarningsViewModel
    @State private var viewModel = PaySlipViewModel()
    
    var body: some View {
        VStack {
            if let slip = viewModel.paySlip {
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 40))
                                .foregroundStyle(.blue)
                            Text("Pay Slip Verified")
                                .font(.title2.bold())
                            Text("Period found: \(slip.periodString)")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top)
                        
                        // Month Selection
                        VStack(alignment: .leading) {
                            Text("Compare against logged month:")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            HStack {
                                Button {
                                    if let prev = Calendar.current.date(byAdding: .month, value: -1, to: viewModel.selectedComparisonMonth) {
                                        viewModel.updateComparisonMonth(prev)
                                    }
                                } label: {
                                    Image(systemName: "chevron.left")
                                }
                                
                                Spacer()
                                Text(viewModel.selectedComparisonMonth, format: .dateTime.month().year())
                                    .font(.headline)
                                Spacer()
                                
                                Button {
                                    if let next = Calendar.current.date(byAdding: .month, value: 1, to: viewModel.selectedComparisonMonth) {
                                        viewModel.updateComparisonMonth(next)
                                    }
                                } label: {
                                    Image(systemName: "chevron.right")
                                }
                            }
                            .padding()
                            .background(Color(UIColor.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal)
                        
                        // Comparison Cards
                        HStack(spacing: 16) {
                            ComparisonCard(
                                title: "Total Hours",
                                slipValue: String(format: "%.2f h", slip.totalHours),
                                appValue: String(format: "%.2f h", viewModel.appTotalHours),
                                diff: viewModel.appTotalHours - slip.totalHours,
                                isCurrency: false
                            )
                            
                            ComparisonCard(
                                title: "Net Pay",
                                slipValue: slip.netPay.formatted(.currency(code: "SEK")),
                                appValue: viewModel.appNetEarnings.formatted(.currency(code: "SEK")),
                                diff: viewModel.appNetEarnings - slip.netPay,
                                isCurrency: true
                            )
                        }
                        .padding(.horizontal)
                        
                        // Extra Pay Slip Details
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Pay Slip Details")
                                .font(.headline)
                            
                            HStack {
                                Text("Gross Pay")
                                Spacer()
                                Text(slip.grossPay.formatted(.currency(code: "SEK")))
                            }
                            HStack {
                                Text("Total Tax")
                                Spacer()
                                Text(slip.totalTax.formatted(.currency(code: "SEK")))
                            }
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                        
                        Button("Upload Another PDF") {
                            viewModel.paySlip = nil
                            viewModel.isImporting = true
                        }
                        .padding(.vertical)
                    }
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                    
                    Text("Pay Slip Verifier")
                        .font(.title.bold())
                    
                    Text("Upload your paystub PDF to verify if your employer paid you correctly based on your logged shifts.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                    
                    Button {
                        viewModel.isImporting = true
                    } label: {
                        Text("Select PDF")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 20)
                    
                    if let error = viewModel.errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                            .padding()
                    }
                }
            }
        }
        .navigationTitle("Pay Slip Verifier")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if viewModel.paySlip == nil {
                viewModel = PaySlipViewModel(earningsViewModel: earningsViewModel)
            }
        }
        .fileImporter(
            isPresented: $viewModel.isImporting,
            allowedContentTypes: [UTType.pdf],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let selectedFile: URL = try result.get().first else { return }
                
                // Need to access securely scoped resources if coming from Files app
                if selectedFile.startAccessingSecurityScopedResource() {
                    defer { selectedFile.stopAccessingSecurityScopedResource() }
                    viewModel.parsePDF(url: selectedFile)
                } else {
                    viewModel.parsePDF(url: selectedFile)
                }
            } catch {
                viewModel.errorMessage = "Failed to select file."
            }
        }
    }
}

struct ComparisonCard: View {
    let title: String
    let slipValue: String
    let appValue: String
    let diff: Double
    let isCurrency: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Paystub")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(slipValue)
                    .font(.headline)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("App")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(appValue)
                    .font(.headline)
            }
            
            Divider()
            
            let diffColor: Color = diff >= -1 && diff <= 1 ? .green : (diff > 1 ? .green : .red)
            let sign = diff > 0 ? "+" : ""
            
            HStack {
                Text("Diff:")
                    .font(.caption)
                Spacer()
                Text("\(sign)\(isCurrency ? diff.formatted(.currency(code: "SEK")) : String(format: "%.2f", diff))")
                    .font(.caption.bold())
                    .foregroundStyle(diffColor)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
