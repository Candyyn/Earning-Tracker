//
//  RollingDigitView.swift
//  LiveTracker
//
//  Created by Emil Magnusson on 2025-08-11.
//
import SwiftUI

struct RollingDigitView: View {
    let digit: Int
    let font: Font
    
    // This @State tracks offset for animation
    @State private var offsetY: CGFloat = 0
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<20) { i in
                Text("\(i % 10)")
                    .font(font)
                    .frame(width: 30, height: 40)
            }
        }
        .offset(y: offsetY)
        .onAppear {
            offsetY = -CGFloat(digit) * 40
        }
        .onChange(of: digit) { oldvalue, newDigit in
            withAnimation(.easeInOut(duration: 0.4)) {
                offsetY = -CGFloat(newDigit) * 40
            }
        }
    }
}

struct AnimatedNumberView: View {
    let number: Double
    let formatter: NumberFormatter
    let font: Font
    
    // Keep digits as @State to trigger view updates
    @State private var digits: [Int] = []
    
    // Store formatted string once per render
    private var formatted: String {
        formatter.string(from: NSNumber(value: number)) ?? ""
    }
    
    func digitsFromString(_ string: String) -> [Int] {
        string.map { char -> Int in
            if let digit = Int(String(char)) {
                return digit
            } else {
                return 10 // sentinel for non-digit chars
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(digits.indices, id: \.self) { i in
                if digits[i] == 10 {
                    // Non-digit character
                    let charIndex = formatted.index(formatted.startIndex, offsetBy: i)
                    Text(String(formatted[charIndex]))
                        .font(font)
                        .frame(width: 20, height: 40)
                } else {
                    RollingDigitView(digit: digits[i], font: font)
                }
            }
        }
        .onAppear {
            digits = digitsFromString(formatted)
        }
        .onChange(of: number) { oldvalue, newValue in
            // Update digits when number changes
            digits = digitsFromString(formatter.string(from: NSNumber(value: newValue)) ?? "")
        }
    }
}

extension View {
    func animatedNumber(_ value: Double, formatter: NumberFormatter, font: Font = .system(size: 40, weight: .bold, design: .monospaced)) -> some View {
        AnimatedNumberView(number: value, formatter: formatter, font: font)
    }
}
