//
//  SecondProgressBar.swift
//  LiveTracker
//
//  Created by Emil Magnusson on 2025-08-12.
//

import SwiftUI
import Combine

struct SecondProgressBar: View {
    @State private var progress: Double = 0
    let timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Color.primary)
                .frame(width: geo.size.width * progress, height: 10)
                .animation(.linear(duration: 0.0), value: progress)
        }
        .frame(width: 100, height: 2)
        .onReceive(timer) { _ in
            let now = Date()
            let fractional = now.timeIntervalSince1970.truncatingRemainder(dividingBy: 1) 
            progress = fractional // update based on exact clock position
        }
    }
}
