import Foundation

enum SwedishMarket {
    static let locale = Locale(identifier: "sv_SE")
    static let timeZone = TimeZone(identifier: "Europe/Stockholm") ?? .current

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        return calendar
    }

    static func currency(_ amount: Decimal, fractionLength: Int = 0) -> String {
        amount.formatted(
            .currency(code: "SEK")
                .locale(locale)
                .precision(.fractionLength(fractionLength))
        )
    }

    static func currencyWithOre(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: "SEK").locale(locale))
    }

    static func hours(_ hours: Double) -> String {
        "\(hours.formatted(.number.locale(locale).precision(.fractionLength(0...1)))) tim"
    }
}
