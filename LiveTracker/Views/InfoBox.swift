//
//  InfoBox.swift
//  LiveTracker
//
//  Created by Emil Magnusson on 2025-09-24.
//

import SwiftUI

struct infoBox: View {
    
    struct LabelShape: Shape {
        let cornerRadius: CGFloat
        let tabWidth: CGFloat
                
        func path(in rect: CGRect) -> Path {
            var path = Path()

            path.move(to: CGPoint(x: rect.width - cornerRadius, y: rect.height))

            path.addArc(
                tangent1End: CGPoint(x: 0, y: rect.height),
                tangent2End: CGPoint(x: 0, y: 0),
                radius: cornerRadius
            )

            path.addArc(
                tangent1End: CGPoint(x: 0, y: 0),
                tangent2End: CGPoint(x: rect.width, y: 0),
                radius: cornerRadius
            )

            path.addArc(
                tangent1End: CGPoint(x: tabWidth, y: 0),
                tangent2End: CGPoint(x: tabWidth, y: rect.height),
                radius: cornerRadius
            )

            path.addArc(
                tangent1End: CGPoint(x: tabWidth, y: cornerRadius * 2 + 10),
                tangent2End: CGPoint(x: rect.width, y: cornerRadius * 2 + 10),
                radius: cornerRadius
            )

            path.addArc(
                tangent1End: CGPoint(x: rect.width, y: cornerRadius * 2 + 10),
                tangent2End: CGPoint(x: rect.width, y: rect.height),
                radius: cornerRadius
            )

            path.addArc(
                tangent1End: CGPoint(x: rect.width, y: rect.height),
                tangent2End: CGPoint(x: 0, y: rect.height),
                radius: cornerRadius
            )

            return path
        }
    }
    
    struct TimeSelectorView: View {
        let options = ["Today", "Week", "Month"]
        @State private var selectedIndex = 0
        @State private var dragOffset: CGFloat = 0
        let width: CGFloat

        var body: some View {
            GeometryReader { geo in
                let itemWidth: CGFloat = 120
                let spacing: CGFloat = 20
                let totalItemWidth = itemWidth + spacing

                HStack(spacing: spacing) {
                    ForEach(options.indices, id: \.self) { index in
                        GeometryReader { itemGeo in
                            let itemCenter = itemGeo.frame(in: .global).midX
                            let screenCenter = geo.frame(in: .global).midX
                            let offsetFromCenter = itemCenter - screenCenter

                            Text(options[index])
                                .frame(width: itemWidth, height: 50)
                                .foregroundColor(selectedIndex == index ? Color.white : Color.white.opacity(0.7))
                                .cornerRadius(12)
                                .scaleEffect(1.0 - min(abs(offsetFromCenter)/300, 0.7))
                                .font(.system(size: 20, weight: .bold))
                        }
                        .frame(width: itemWidth, height: 50)
                    }
                }
                .frame(width: CGFloat(options.count) * (itemWidth + spacing) - spacing, alignment: .leading)
                // Center the selected item dynamically
                .offset(x: dragOffset - CGFloat(selectedIndex) * totalItemWidth + (width - itemWidth)/2)
                .animation(.easeOut(duration: 0.3), value: dragOffset)
                .animation(.easeOut(duration: 0.3), value: selectedIndex)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation.width
                        }
                        .onEnded { value in
                            dragOffset = 0
                            let rawIndex = (CGFloat(selectedIndex) * totalItemWidth - value.translation.width) / totalItemWidth
                            let nearestIndex = min(max(Int(round(rawIndex)), 0), options.count - 1)
                            selectedIndex = nearestIndex
                        }
                )
            }
            .mask(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.2),
                        .init(color: .black, location: 0.8),
                        .init(color: .clear, location: 1)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: width, height: 50)
        }
    }


    
    
    var body: some View {
        
        
        GeometryReader { geometry in
            let width = geometry.size.width - 10
            let height = (geometry.size.height / 2)
            let centerX = geometry.size.width / 2
            let centerY = geometry.size.height * 3/4
            let heightTitle = height + ((20 * 2 + 10) / 2)
            
            GlassEffectContainer() {
                LabelShape(cornerRadius: 20, tabWidth: centerX)
                    .glassEffect(in: LabelShape(cornerRadius: 20, tabWidth: centerX))
                    .frame(width: width, height: height)
                    .position(x: centerX, y: centerY)
            }
            
            TimeSelectorView(width: 150)
                //.position(x: (centerX * 2) - (150 / 2), y: height + ((20 * 2 + 20) / 2))
                //.position(x: centerX, y: centerY - 400)
                .position(x: centerX * 3/2, y: heightTitle)
            
            HStack(alignment: .center, spacing: 4) {
                Text("Todays Earning")
                    .font(.system(size: 20, weight: .bold))
            }
            .position(x: centerX / 2, y: heightTitle)
            .padding(4)
            
        }
        
    }
}
