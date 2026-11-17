//
//  EventResponseLinkTests.swift
//  MeetingBar
//

import XCTest
@testable import MeetingBarLogic

final class EventResponseLinkTests: XCTestCase {
    func testOnlySelfAttendeeResponseChanges() throws {
        let attendees: [[String: Any]] = [
            ["email": "me@x.com", "self": true, "responseStatus": "needsAction"],
            ["email": "room@x.com", "resource": true, "responseStatus": "accepted"],
            ["email": "other@x.com", "responseStatus": "declined"]
        ]
        let updated = try XCTUnwrap(EventResponsePolicy.googleAttendees(attendees, responding: .maybe))
        XCTAssertEqual(updated.compactMap { $0["responseStatus"] as? String }, ["tentative", "accepted", "declined"])
        XCTAssertEqual(updated.count, 3)
    }

    func testNotAnAttendeeReturnsNil() {
        XCTAssertNil(EventResponsePolicy.googleAttendees([["email": "a@x.com"]], responding: .accept))
    }
}
