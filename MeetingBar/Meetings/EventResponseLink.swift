//
//  EventResponseLink.swift
//  MeetingBar
//
//  Accept / Maybe / Decline for invites. With the Google Calendar provider the
//  answer is sent through the Calendar API in the background. EventKit can't
//  change a participant's status, so with the macOS Calendar source the event
//  is opened in Calendar to answer there.
//

import Foundation

public enum EventResponse: String, CaseIterable, Sendable {
    case accept = "accepted"
    case decline = "declined"
    case maybe = "tentative"

    /// Google Calendar API `responseStatus` value.
    public var googleResponseStatus: String { rawValue }
}

public struct EventResponseRequest: Sendable {
    public let response: EventResponse
    public let eventID: String
    public let calendarID: String
    /// Calendar app / Google Calendar page for the event, used when the
    /// answer can't be sent in the background.
    public let fallbackURL: URL?
}

public enum EventResponsePolicy {
    /// Sets the current user's `responseStatus` in a Google event's attendee
    /// list, leaving every other attendee untouched. Nil when the user isn't
    /// an attendee (nothing to answer).
    public static func googleAttendees(
        _ attendees: [[String: Any]], responding response: EventResponse
    ) -> [[String: Any]]? {
        guard attendees.contains(where: { $0["self"] as? Bool == true }) else { return nil }
        return attendees.map { attendee in
            guard attendee["self"] as? Bool == true else { return attendee }
            var updated = attendee
            updated["responseStatus"] = response.googleResponseStatus
            return updated
        }
    }
}
