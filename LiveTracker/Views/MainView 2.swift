//
//  MainView.swift
//  Tracker
//
//  Created by Emil Magnusson on 2025-08-11.
//
import SwiftUI

struct WorkEntry: Identifiable {
    let id = UUID()
    let companyName: String
    let logoURL: URL
    let hours: Double
    let date: Date
    let amount: Double
}

struct ContentView: View {
    @State private var entries: [WorkEntry] = [
        WorkEntry(
            companyName: "Atea - SOC",
            logoURL: URL(string: "https://cdn.brandfetch.io/idxjw4fWHP/w/1921/h/1921/theme/dark/icon.jpeg?c=1dxbfHSJFAPEGdCLU4o5B")!,
            hours: 8,
            date: .now,
            amount: 100.00
        ),
        WorkEntry(
            companyName: "Spotify",
            logoURL: URL(string: "https://upload.wikimedia.org/wikipedia/commons/1/19/Spotify_logo_without_text.svg")!,
            hours: 6.5,
            date: .now.addingTimeInterval(-86400),
            amount: 85.50
        ),
        WorkEntry(
            companyName: "Tesla",
            logoURL: URL(string: "https://upload.wikimedia.org/wikipedia/commons/b/bd/Tesla_Motors.svg")!,
            hours: 9,
            date: .now.addingTimeInterval(-172800),
            amount: 120.00
        )
    ]
    
    var body: some View {
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    Color(.systemBackground)
                        .ignoresSafeArea()
                    
                    Text("Main Content Here")
                        .font(.largeTitle)
                    
                    BottomSheet(entries: entries, screenHeight: geometry.size.height)
                }
            }
        }
}

struct BottomSheet: View {
    let entries: [WorkEntry]
    let screenHeight: CGFloat
    
    @State private var offsetY: CGFloat = 0
    @State private var lastOffset: CGFloat = 0
    
    let minHeightRatio: CGFloat = 0.22 // collapsed height ratio
    let maxHeightRatio: CGFloat = 0.8  // max height ratio
    
    var body: some View {
        let minOffset = screenHeight * (1 - maxHeightRatio)
        let maxOffset = screenHeight * (1 - minHeightRatio)
        
        VStack(spacing: 0) {
            // Drag handle
            RoundedRectangle(cornerRadius: 3)
                .frame(width: 40, height: 5)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
                .padding(.bottom, 8)
            
            Text("This month")
                .font(.headline)
                .padding(.bottom, 8)
            
            Divider()
            
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(entries) { entry in
                        WorkEntryRow(entry: entry)
                            .padding(.horizontal)   // inner horizontal padding
                            .padding(.vertical, 6) // inner vertical padding
                        
                        if entry.id != entries.last?.id {
                            Divider()
                                .padding(.horizontal)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.thinMaterial) // card-like background
                )
                .padding(.horizontal) // outer padding for the card
                .padding(.vertical, 8)
            }
            .frame(maxHeight: screenHeight * maxHeightRatio - 50)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .offset(y: offsetY)
        .gesture(
            DragGesture()
                .onChanged { value in
                    let newOffset = lastOffset + value.translation.height
                    // Clamp offset to min/max
                    offsetY = max(minOffset, min(newOffset, maxOffset))
                }
                .onEnded { value in
                    // Snap to either collapsed or expanded based on velocity & position
                    let midpoint = (minOffset + maxOffset) / 2
                    if offsetY < midpoint {
                        offsetY = minOffset
                    } else {
                        offsetY = maxOffset
                    }
                    lastOffset = offsetY
                }
        )
        .onAppear {
            offsetY = maxOffset // start near the bottom
            lastOffset = offsetY
        }
        .frame(maxWidth: .infinity)
        .animation(.interactiveSpring(), value: offsetY)
    }
}

struct WorkEntryRow: View {
    let entry: WorkEntry
    
    var body: some View {
        HStack(spacing: 16) {
            AsyncImage(url: entry.logoURL) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(.thinMaterial))
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(.separator, lineWidth: 0.5))
                case .failure:
                    Image(systemName: "building.2.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .padding(8)
                        .background(Circle().fill(.thinMaterial))
                @unknown default:
                    EmptyView()
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.companyName)
                    .font(.headline)
                Text(entry.date, style: .date)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(entry.hours, specifier: "%.1f") hours")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text("\(entry.amount, format: .currency(code: "SEK"))")
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    ContentView()
}


