//
//  EarningsWidgetLiveActivity.swift
//  EarningsWidget
//
//  Created by Emil Magnusson on 2025-10-01.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct EarningsWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct EarningsWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EarningsWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension EarningsWidgetAttributes {
    fileprivate static var preview: EarningsWidgetAttributes {
        EarningsWidgetAttributes(name: "World")
    }
}

extension EarningsWidgetAttributes.ContentState {
    fileprivate static var smiley: EarningsWidgetAttributes.ContentState {
        EarningsWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: EarningsWidgetAttributes.ContentState {
         EarningsWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: EarningsWidgetAttributes.preview) {
   EarningsWidgetLiveActivity()
} contentStates: {
    EarningsWidgetAttributes.ContentState.smiley
    EarningsWidgetAttributes.ContentState.starEyes
}
