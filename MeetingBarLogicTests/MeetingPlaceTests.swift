import XCTest
@testable import MeetingBarLogic

final class MeetingPlaceTests: XCTestCase {
    func testFriendlyRoomNameDropsCodesCapacityAndTags() {
        XCTAssertEqual(MeetingPlacePolicy.friendlyRoomName("LON-12-Abbey Road (8) [VC]"), "Abbey Road")
        XCTAssertEqual(MeetingPlacePolicy.friendlyRoomName("Blue Room"), "Blue Room")
        XCTAssertEqual(MeetingPlacePolicy.friendlyRoomName("Stockholm-Blue room (6)"), "Stockholm - Blue room")
    }

    func testPlacesPreferRoomsAndSkipVirtualLocations() {
        XCTAssertEqual(MeetingPlacePolicy.places(rooms: ["NYC-4-Hudson (4)"], location: "Kitchen"), ["Hudson"])
        XCTAssertEqual(MeetingPlacePolicy.places(rooms: [], location: "Kitchen, 3rd floor"), ["Kitchen, 3rd floor"])
        XCTAssertEqual(MeetingPlacePolicy.places(rooms: [], location: "https://meet.google.com/abc"), [])
    }

    func testOfficeDaysModeHidesOnlyKnownRemoteDays() {
        XCTAssertTrue(MeetingPlacePolicy.shouldShow(mode: .officeDays, workingLocation: nil))
        XCTAssertTrue(MeetingPlacePolicy.shouldShow(mode: .officeDays, workingLocation: .office))
        XCTAssertFalse(MeetingPlacePolicy.shouldShow(mode: .officeDays, workingLocation: .home))
        XCTAssertFalse(MeetingPlacePolicy.shouldShow(mode: .off, workingLocation: .office))
        XCTAssertTrue(MeetingPlacePolicy.shouldShow(mode: .always, workingLocation: .home))
    }
}
