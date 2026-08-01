import Foundation

public struct PreferenceSaveQueue: Sendable {
    public private(set) var confirmed: UserPreferences
    public private(set) var inFlight: UserPreferences?
    public private(set) var queued: UserPreferences?

    public init(confirmed: UserPreferences) {
        self.confirmed = confirmed
    }

    public mutating func reset(confirmed: UserPreferences) {
        self.confirmed = confirmed
        inFlight = nil
        queued = nil
    }

    public mutating func enqueue(_ preferences: UserPreferences) -> UserPreferences? {
        guard let inFlight else {
            guard preferences != confirmed else { return nil }
            self.inFlight = preferences
            return preferences
        }

        queued = preferences == inFlight ? nil : preferences
        return nil
    }

    public mutating func didSave(_ preferences: UserPreferences) -> UserPreferences? {
        guard inFlight == preferences else { return nil }
        confirmed = preferences
        inFlight = nil

        guard let queued else { return nil }
        self.queued = nil
        guard queued != confirmed else { return nil }
        inFlight = queued
        return queued
    }

    public mutating func didFail(_ preferences: UserPreferences) -> UserPreferences? {
        guard inFlight == preferences else { return nil }
        inFlight = nil
        queued = nil
        return confirmed
    }
}
