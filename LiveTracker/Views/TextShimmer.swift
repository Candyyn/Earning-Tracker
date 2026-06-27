//
//  TextShimmer.swift
//  LiveTracker
//
//  Created by Emil Magnusson on 2026-06-25.
//

import SwiftUI

struct TextShimmer: View {
    var vm: EarningsViewModel
    let duration: Double
    
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    private var shimmerColor: Color {
        let type = vm.currentShiftType
        switch type {
        case .day: return .secondary
        case .evening: return .orange
        case .night: return .indigo
        case .weekend: return .pink
        case .holiday, .holidayMajor: return .red
        }
    }

    var body: some View {
        let text = "\(ModernMainView.currencyFormatter.string(from: vm.currentlyHourly as NSNumber) ?? "")/h \(vm.isOnBreak() ? " - Break" : "")"
        
        ZStack {
            Text(text)
                .contentTransition(.numericText(value: vm.currentlyHourly))
                .animation(.default, value: vm.currentEarnings)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
            
            if !reduceMotion {
                Text(text)
                    .contentTransition(.numericText(value: vm.currentlyHourly))
                    .animation(.default, value: vm.currentEarnings)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(shimmerColor)
                    .phaseAnimator([false, true]) { content, phase in
                        content
                            .mask {
                                Rectangle()
                                    .fill(LinearGradient(gradient: Gradient(colors: [.clear, .black, .clear]), startPoint: .leading, endPoint: .trailing))
                                    .frame(width: 100)
                                    .rotationEffect(.degrees(20))
                                    .offset(x: phase ? 200 : -200)
                            }
                    } animation: { phase in
                        .linear(duration: duration)
                    }
            }
        }
    }
}
