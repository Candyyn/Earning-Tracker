import Foundation

extension Decimal {
    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }

    func multiplied(by scalar: Double) -> Decimal {
        self * Decimal(scalar)
    }
}
