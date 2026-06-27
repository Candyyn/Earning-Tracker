//
//  EarningsAuraView.swift
//  LiveTracker
//
//  Created by Emil Magnusson on 2025-10-01.
//

import SwiftUI

struct EarningsAuraView: View {
    var shiftType: ShiftType
    var progress: Double // 0.0 to 1.0 (Current Earnings / Monthly Goal)
    
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    @State private var rotation: Double = 0.0
    @State private var scale: CGFloat = 1.0
    
    private var baseColor: Color {
        switch shiftType {
        case .night: return .indigo
        case .evening: return .orange
        case .weekend: return .pink
        case .holiday, .holidayMajor: return .red
        default: return .blue // day
        }
    }
    
    private var secondaryColor: Color {
        switch shiftType {
        case .night: return .purple
        case .evening: return .yellow
        case .weekend: return .purple
        case .holiday, .holidayMajor: return .orange
        default: return .cyan
        }
    }

    var body: some View {
        ZStack {
            // Background glow
            Circle()
                .fill(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            baseColor,
                            secondaryColor,
                            baseColor.opacity(0.5),
                            secondaryColor.opacity(0.8),
                            baseColor
                        ]),
                        center: .center,
                        angle: .degrees(rotation)
                    )
                )
                .blur(radius: 60)
                .scaleEffect(scale * 1.2)
                .opacity(0.4 + (progress * 0.4)) // Gets brighter as progress increases
            
            // Core orb
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [Color.white.opacity(0.6), baseColor.opacity(0.4)]),
                        center: .center,
                        startRadius: 10,
                        endRadius: 150
                    )
                )
                .frame(width: 150 + CGFloat(progress * 150), height: 150 + CGFloat(progress * 150))
                .blur(radius: 20)
                .scaleEffect(scale)
        }
        .onAppear {
            if !reduceMotion {
                withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) {
                    rotation = 360.0
                }
                withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                    scale = 1.15
                }
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        EarningsAuraView(shiftType: .weekend, progress: 0.3)
    }
}
