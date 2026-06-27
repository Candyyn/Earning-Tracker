//
//  EarningsWidget.swift
//  EarningsWidget
//
//  Created by Emil Magnusson on 2025-10-01.
//

import WidgetKit
import SwiftUI

struct EarningsEntry: TimelineEntry {
    let date: Date
    let earnings: Double
}

class EarningsData {
    static let shared = EarningsData()
    
    func loadEarnings() -> Double {
        let defaults = UserDefaults(suiteName: "group.studio.magnusson.livetracker")
        return defaults?.double(forKey: "currentEarnings") ?? 0
    }
}


struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> EarningsEntry {
        EarningsEntry(date: Date(), earnings: 1234.56)
    }

    func getSnapshot(in context: Context, completion: @escaping (EarningsEntry) -> Void) {
        completion(EarningsEntry(date: Date(), earnings: 1234.56))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EarningsEntry>) -> Void) {
        // Ideally fetch from shared storage (App Groups)
        let currentEarnings = EarningsData.shared.loadEarnings()
        let entry = EarningsEntry(date: Date(), earnings: currentEarnings)

        // Refresh in 15 minutes
        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(900)))
        completion(timeline)
    }
}

struct EarningsWidgetEntryView: View {
    var entry: EarningsEntry
    
    var body: some View {
        VStack {
            Text("This Month's Earnings")
                .font(.caption)
            Text("\(entry.earnings, format: .currency(code: "SEK"))")
                .font(.title3)
                .bold()
                .privacySensitive()
        }
        .padding()
        .containerBackground(for: .widget) {   // 👈 required for widgets
            Color.clear
        }
    }
}

struct EarningsWidget: Widget {
    let kind: String = "EarningsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            EarningsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Earnings")
        .description("Shows your current earnings.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

