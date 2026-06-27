import Foundation
import ActivityKit

public struct EarningsWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var earnedSoFar: Double
        public var currentRate: Double
        public var shiftType: ShiftType
        
        public init(earnedSoFar: Double, currentRate: Double, shiftType: ShiftType) {
            self.earnedSoFar = earnedSoFar
            self.currentRate = currentRate
            self.shiftType = shiftType
        }
    }

    public var shiftStart: Date
    
    public init(shiftStart: Date) {
        self.shiftStart = shiftStart
    }
}
