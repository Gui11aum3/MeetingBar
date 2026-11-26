//
//  MeetingPlace.swift
//  MeetingBar
//
//  Where a meeting happens in person: booked rooms (friendly names) or the
//  event's physical location, and whether to show it for the day's working
//  location.
//

import Foundation

public enum WorkingLocationKind: String, Codable, Sendable {
    case office, home, other
}

public enum MeetingPlaceChipMode: String, CaseIterable, Sendable {
    case off, officeDays, always
}

public enum MeetingPlacePolicy {
    /// "LON-12-Abbey Road (8) [VC]" -> "Abbey Road": drops capacity "(8)",
    /// tags "[VC]" and leading building/floor codes.
    public static func friendlyRoomName(_ raw: String) -> String {
        var name = raw.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
        name = name.replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
        var parts = name.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
        while parts.count > 1, let first = parts.first, isCode(first) {
            parts.removeFirst()
        }
        let friendly = parts.joined(separator: " - ").trimmingCharacters(in: .whitespaces)
        return friendly.isEmpty ? raw.trimmingCharacters(in: .whitespaces) : friendly
    }

    private static func isCode(_ part: String) -> Bool {
        !part.isEmpty && part.count <= 6
            && part.allSatisfy { $0.isNumber || ($0.isLetter && $0.isUppercase) }
    }

    /// A location people can walk to, not a meeting URL or dial-in.
    public static func physicalLocation(_ location: String?) -> String? {
        guard let trimmed = location?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        let lowered = trimmed.lowercased()
        let virtualMarkers = ["http://", "https://", "meet.google", "zoom.us", "teams.microsoft", "webex"]
        guard !virtualMarkers.contains(where: lowered.contains) else { return nil }
        return trimmed
    }

    /// Rooms first; the location only when no room is booked.
    public static func places(rooms: [String], location: String?) -> [String] {
        if !rooms.isEmpty { return rooms.map(friendlyRoomName) }
        return physicalLocation(location).map { [$0] } ?? []
    }

    /// On office days (or when the day's working location is unknown) show
    /// places; hide them only on days known to be remote.
    public static func shouldShow(mode: MeetingPlaceChipMode, workingLocation: WorkingLocationKind?) -> Bool {
        switch mode {
        case .off: return false
        case .always: return true
        case .officeDays: return workingLocation == nil || workingLocation == .office
        }
    }

    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
