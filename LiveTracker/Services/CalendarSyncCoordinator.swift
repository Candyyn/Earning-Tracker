import Foundation
import Observation

enum CalendarSyncState: Equatable {
    case disconnected
    case denied
    case connected
    case syncing
    case failed(String)

    var title: String {
        switch self {
        case .disconnected: "Inte ansluten"
        case .denied: "Åtkomst nekad"
        case .connected: "Ansluten"
        case .syncing: "Synkar"
        case .failed: "Synk misslyckades"
        }
    }

    var systemImage: String {
        switch self {
        case .disconnected: "calendar.badge.plus"
        case .denied: "calendar.badge.exclamationmark"
        case .connected: "calendar.badge.checkmark"
        case .syncing: "arrow.trianglehead.2.clockwise.rotate.90"
        case .failed: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
        }
    }
}

@Observable
@MainActor
final class CalendarSyncCoordinator {
    private(set) var state: CalendarSyncState
    private(set) var isEnabled: Bool

    private let calendarService: CalendarProviding
    private let defaults: UserDefaults
    private static let enabledKey = "CalendarSyncEnabled"

    init(calendarService: CalendarProviding, defaults: UserDefaults = .standard) {
        self.calendarService = calendarService
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: Self.enabledKey)
        self.state = .disconnected
        refreshAuthorizationState()
    }

    var shouldSynchronize: Bool {
        isEnabled && calendarService.authorizationStatus == .fullAccess
    }

    func refreshAuthorizationState() {
        switch calendarService.authorizationStatus {
        case .fullAccess where isEnabled:
            state = .connected
        case .denied:
            state = .denied
        case .notDetermined, .fullAccess, .unavailable:
            state = .disconnected
        }
    }

    func connect() async throws {
        state = .syncing
        do {
            try await calendarService.requestAccess()
            isEnabled = true
            defaults.set(true, forKey: Self.enabledKey)
            refreshAuthorizationState()
        } catch {
            isEnabled = false
            defaults.set(false, forKey: Self.enabledKey)
            refreshAuthorizationState()
            if calendarService.authorizationStatus != .denied {
                state = .failed(error.localizedDescription)
            }
            throw error
        }
    }

    func disconnect() {
        isEnabled = false
        defaults.set(false, forKey: Self.enabledKey)
        refreshAuthorizationState()
    }

    func performSync(_ operation: () async throws -> Void) async throws {
        guard shouldSynchronize else {
            refreshAuthorizationState()
            return
        }

        state = .syncing
        do {
            try await operation()
            state = .connected
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    func recordSyncStarted() {
        guard shouldSynchronize else { return }
        state = .syncing
    }

    func recordSyncSucceeded() {
        refreshAuthorizationState()
    }

    func recordSyncFailure(_ error: Error) {
        state = .failed(error.localizedDescription)
    }
}
