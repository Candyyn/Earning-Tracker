import Foundation

struct PaySlip: Identifiable {
    let id = UUID()
    
    /// The period parsed from the PDF, e.g., "2026 06"
    var periodString: String
    
    /// The actual target month we want to compare against (defaults to the month before the periodString)
    var targetComparisonMonth: Date
    
    /// Total worked hours extracted from the slip (e.g., sum of all 'Timlön' rows)
    var totalHours: Double
    
    /// Gross pay before taxes ("Lön efter bruttoavdrag")
    var grossPay: Double
    
    /// Net pay to the bank account ("Att Utbetala")
    var netPay: Double
    
    /// Total tax deducted ("Preliminär skatt")
    var totalTax: Double
    
    /// Any parsed discrepancies or missing expected fields
    var parsingNotes: [String] = []
}
