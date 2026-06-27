import Foundation
import PDFKit

enum PDFParserError: Error {
    case invalidPDF
    case emptyText
    case periodNotFound
}

class PDFParserService {
    static let shared = PDFParserService()
    
    private static let periodRegex = try? NSRegularExpression(pattern: "Löneperiod:\\s*(\\d{4}\\s*\\d{2})")
    private static let fallbackRegex = try? NSRegularExpression(pattern: "(\\d{4}\\s*\\d{2})")
    private static let hoursRegex = try? NSRegularExpression(pattern: "(?i)Timlön.*?(\\d+[,.]\\d+)\\s*Tim")
    private static let moneyRegex = try? NSRegularExpression(pattern: "(-?\\d{1,3}(?:\\s?\\d{3})*[,.]\\d{2})")
    
    private init() {}
    
    func parsePaySlip(from url: URL) throws -> PaySlip {
        guard let document = PDFDocument(url: url), let text = document.string else {
            throw PDFParserError.invalidPDF
        }
        
        guard !text.isEmpty else {
            throw PDFParserError.emptyText
        }
        
        return try parseText(text)
    }
    
    func parseText(_ text: String) throws -> PaySlip {
        guard let periodRegex = Self.periodRegex,
              let fallbackRegex = Self.fallbackRegex,
              let hoursRegex = Self.hoursRegex,
              let moneyRegex = Self.moneyRegex else {
            throw PDFParserError.invalidPDF
        }
        
        var notes: [String] = []
        
        // 1. Parse Period
        // Looking for "Löneperiod: 2026 06"
        let periodString: String
        if let match = periodRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let range = Range(match.range(at: 1), in: text) {
                periodString = String(text[range])
            } else {
                periodString = ""
            }
        } else {
            // Fallback: look for just 4 digits space 2 digits
            if let match = fallbackRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let range = Range(match.range(at: 1), in: text) {
                periodString = String(text[range])
                notes.append("Found period using fallback regex.")
            } else {
                throw PDFParserError.periodNotFound
            }
        }
        
        // Target month is typically the month *before* the Löneperiod in Sweden.
        var targetMonth = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy MM"
        if let date = formatter.date(from: periodString.replacingOccurrences(of: " ", with: " ")) {
            if let prevMonth = Calendar.current.date(byAdding: .month, value: -1, to: date) {
                targetMonth = prevMonth
            } else {
                targetMonth = date
            }
        }
        
        // 2. Parse Total Hours
        // Looking for "Timlön 8,00Tim" etc.
        let hourMatches = hoursRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        
        var totalHours: Double = 0
        for match in hourMatches {
            if let range = Range(match.range(at: 1), in: text) {
                let hourStr = String(text[range]).replacingOccurrences(of: ",", with: ".")
                if let hour = Double(hourStr) {
                    totalHours += hour
                }
            }
        }
        
        // 3. Parse Gross Pay (Lön efter bruttoavdrag)
        // Usually a large positive number. Let's find all numbers with two decimals and a comma, possibly with spaces.
        // e.g. 14511,46 or 14 511,46
        var grossPay: Double = 0
        var netPay: Double = 0
        var totalTax: Double = 0
        
        // Extract all monetary values: numbers that might have a space for thousands and a comma for decimals.
        // E.g. "1 528,00", "-3 869,00", "14511,46"
        let moneyMatches = moneyRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        
        var allValues: [Double] = []
        for match in moneyMatches {
            if let range = Range(match.range(at: 1), in: text) {
                let str = String(text[range])
                    .replacingOccurrences(of: " ", with: "")
                    .replacingOccurrences(of: ",", with: ".")
                if let val = Double(str) {
                    allValues.append(val)
                }
            }
        }
        
        // Heuristics to find Gross, Net, Tax:
        // Net pay is usually the "Att Utbetala" which is a positive value, often at the end.
        // Let's try to parse specifically from context if possible.
        
        // For Gross Pay ("Lön efter bruttoavdrag"): 
        let lines = text.components(separatedBy: .newlines)
        
        func extractNumberNear(keyword: String, isNegative: Bool = false) -> Double? {
            // Find line with keyword
            for (index, line) in lines.enumerated() {
                if line.lowercased().contains(keyword.lowercased()) {
                    // Try to find a number on this line
                    let match = moneyRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line))
                    if let m = match, let range = Range(m.range(at: 1), in: line) {
                        let str = String(line[range]).replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".")
                        return Double(str)
                    }
                    // Try next line
                    if index + 1 < lines.count {
                        let nextLine = lines[index + 1]
                        let nextMatch = moneyRegex.firstMatch(in: nextLine, range: NSRange(nextLine.startIndex..., in: nextLine))
                        if let nm = nextMatch, let range = Range(nm.range(at: 1), in: nextLine) {
                            let str = String(nextLine[range]).replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".")
                            return Double(str)
                        }
                    }
                }
            }
            return nil
        }
        
        grossPay = extractNumberNear(keyword: "Lön efter bruttoavdrag") ?? 0
        netPay = extractNumberNear(keyword: "Att Utbetala") ?? 0
        
        // Sum all negative values to approximate tax if "Preliminär skatt" isn't nicely placed
        var foundTaxes: [Double] = []
        for line in lines {
            if line.lowercased().contains("preliminär skatt") {
                let match = moneyRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line))
                if let m = match, let range = Range(m.range(at: 1), in: line) {
                    let str = String(line[range]).replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".")
                    if let v = Double(str), v < 0 {
                        foundTaxes.append(v)
                    }
                }
            }
        }
        
        if foundTaxes.isEmpty {
            totalTax = extractNumberNear(keyword: "skatt") ?? 0
            if totalTax > 0 { totalTax = -totalTax }
        } else {
            totalTax = foundTaxes.reduce(0, +)
        }
        
        if grossPay == 0 {
            // Fallback: largest positive value
            grossPay = allValues.max() ?? 0
            notes.append("Gross pay estimated by finding the maximum value.")
        }
        
        if netPay == 0 {
            // Fallback: second largest positive value if it exists, or just look for "Utbetala"
            notes.append("Net pay might be inaccurate. Could not explicitly find 'Att Utbetala'.")
        }
        
        return PaySlip(
            periodString: periodString,
            targetComparisonMonth: targetMonth,
            totalHours: totalHours,
            grossPay: grossPay,
            netPay: netPay,
            totalTax: totalTax,
            parsingNotes: notes
        )
    }
}
