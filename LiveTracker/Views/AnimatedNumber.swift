//
//  AnimatedNumber.swift
//  Tracker
//
//  Created by Emil Magnusson on 2025-08-11.
//

import SwiftUI

struct AnimatedNumber: AnimatableModifier {
    var value: Double
    var formatter: NumberFormatter
    
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    
    func body(content: Content) -> some View {
        Text(formatter.string(from: NSNumber(value: value)) ?? "")
            .font(.system(size: 40, weight: .bold))
    }
}

extension View {
    func animatedNumber(_ value: Double, formatter: NumberFormatter) -> some View {
        self.modifier(AnimatedNumber(value: value, formatter: formatter))
    }
}
