import Foundation
import Observation
import SwiftUI
import SwiftData

@Observable
class PaySlipViewModel {
    var paySlip: PaySlip?
    var isImporting = false
    var errorMessage: String?
    
    // The manually selected month to compare against, defaulting to the slip's target
    var selectedComparisonMonth: Date = Date()
    
    var appTotalHours: Double = 0
    var appNetEarnings: Double = 0
    
    // Dependencies
    private weak var earningsViewModel: EarningsViewModel?
    
    init(earningsViewModel: EarningsViewModel? = nil) {
        self.earningsViewModel = earningsViewModel
    }
    
    func parsePDF(url: URL) {
        do {
            let slip = try PDFParserService.shared.parsePaySlip(from: url)
            self.paySlip = slip
            self.selectedComparisonMonth = slip.targetComparisonMonth
            self.errorMessage = nil
            calculateAppTotals()
        } catch {
            self.errorMessage = "Failed to parse Pay Slip: \(error.localizedDescription)"
        }
    }
    
    func calculateAppTotals() {
        guard let evm = earningsViewModel else { return }
        
        let calendar = Calendar.current
        let descriptor = FetchDescriptor<Shift>()
        guard let allShifts = try? evm.modelContext.fetch(descriptor) else { return }
        
        let shifts = allShifts.filter { shift in
            calendar.component(.month, from: shift.start) == calendar.component(.month, from: selectedComparisonMonth) &&
            calendar.component(.year, from: shift.start) == calendar.component(.year, from: selectedComparisonMonth)
        }.sorted { $0.start < $1.start }
        
        // Calculate total hours
        var totalSeconds: TimeInterval = 0
        for shift in shifts {
            for (start, end) in evm.calculator.workSegments(for: shift, workedUntil: shift.end) {
                totalSeconds += end.timeIntervalSince(start)
            }
        }
        
        self.appTotalHours = totalSeconds / 3600.0
        self.appNetEarnings = evm.totalEarningsForShifts(shifts)
    }
    
    func updateComparisonMonth(_ month: Date) {
        self.selectedComparisonMonth = month
        calculateAppTotals()
    }
}
