//
//  EarningsWidgetLiveActivity.swift
//  EarningsWidget
//
//  Created by Emil Magnusson on 2025-10-01.
//

import ActivityKit
import WidgetKit
import SwiftUI



struct EarningsWidgetLiveActivity: Widget {
    
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EarningsWidgetAttributes.self) { context in
            // Lock screen/banner UI
            HStack {
                VStack(alignment: .leading) {
                    Text("LiveTracker")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("\(context.state.shiftType.displayName) Shift")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text(context.state.earnedSoFar, format: .currency(code: "SEK"))
                        .font(.title3)
                        .bold()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(value: context.state.earnedSoFar))
                        .privacySensitive()
                    
                    Text(context.attributes.shiftStart, style: .timer)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.8))
            .activitySystemActionForegroundColor(Color.white)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading) {
                        Text("Earned")
                            .font(.caption2)
                            .foregroundStyle(.gray)
                        Text(context.state.earnedSoFar, format: .currency(code: "SEK"))
                            .font(.headline)
                            .foregroundStyle(.white)
                            .contentTransition(.numericText(value: context.state.earnedSoFar))
                            .privacySensitive()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing) {
                        Text("Rate")
                            .font(.caption2)
                            .foregroundStyle(.gray)
                        Text("\(context.state.currentRate.formatted(.currency(code: "SEK")))/h")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .contentTransition(.numericText(value: context.state.currentRate))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.shiftType.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                        Spacer()
                        Text(context.attributes.shiftStart, style: .timer)
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.blue)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: "briefcase.fill")
                    .foregroundStyle(.blue)
            } compactTrailing: {
                Text(context.attributes.shiftStart, style: .timer)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.white)
            } minimal: {
                Image(systemName: "briefcase.fill")
                    .foregroundStyle(.blue)
            }
            .widgetURL(URL(string: "livetracker://"))
            .keylineTint(Color.blue)
        }
    }
}

extension EarningsWidgetAttributes {
    fileprivate static var preview: EarningsWidgetAttributes {
        EarningsWidgetAttributes(shiftStart: Date().addingTimeInterval(-3600))
    }
}

extension EarningsWidgetAttributes.ContentState {
    fileprivate static var active: EarningsWidgetAttributes.ContentState {
        EarningsWidgetAttributes.ContentState(earnedSoFar: 250.50, currentRate: 150.0, shiftType: .evening)
     }
}

#Preview("Notification", as: .content, using: EarningsWidgetAttributes.preview) {
   EarningsWidgetLiveActivity()
} contentStates: {
    EarningsWidgetAttributes.ContentState.active
}
