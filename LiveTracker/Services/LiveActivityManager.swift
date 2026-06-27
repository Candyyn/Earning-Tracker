import Foundation
import ActivityKit

class LiveActivityManager {
    static let shared = LiveActivityManager()
    
    private var currentActivity: Activity<EarningsWidgetAttributes>?
    private var lastActivityUpdateTotal: Double = -1
    private var updateTask: Task<Void, Never>?
    
    private init() {}
    
    func manageLiveActivity(for shift: Shift?, activeTotal: Double, currentRate: Double, shiftType: ShiftType) {
        if currentActivity == nil {
            currentActivity = Activity<EarningsWidgetAttributes>.activities.first
        }
        
        guard let shift = shift else {
            // End activity if one exists
            if let activity = currentActivity {
                let state = EarningsWidgetAttributes.ContentState(earnedSoFar: activeTotal, currentRate: currentRate, shiftType: shiftType)
                updateTask?.cancel()
                updateTask = Task {
                    await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .default)
                }
                currentActivity = nil
            }
            return
        }
        
        let state = EarningsWidgetAttributes.ContentState(
            earnedSoFar: activeTotal,
            currentRate: currentRate,
            shiftType: shiftType
        )
        
        if let activity = currentActivity {
            // Only update if difference is >= 1 kr to avoid throttling
            if abs(activeTotal - lastActivityUpdateTotal) >= 1.0 {
                lastActivityUpdateTotal = activeTotal
                updateTask?.cancel()
                updateTask = Task {
                    await activity.update(ActivityContent(state: state, staleDate: nil))
                }
            }
        } else {
            // Start new activity
            if ActivityAuthorizationInfo().areActivitiesEnabled {
                let attributes = EarningsWidgetAttributes(shiftStart: shift.start)
                do {
                    lastActivityUpdateTotal = activeTotal
                    currentActivity = try Activity.request(
                        attributes: attributes,
                        content: ActivityContent(state: state, staleDate: nil),
                        pushType: nil
                    )
                } catch {
                    print("Failed to start Live Activity: \(error)")
                }
            }
        }
    }
}
