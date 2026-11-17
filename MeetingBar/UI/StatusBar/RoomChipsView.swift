//
//  RoomChipsView.swift
//  MeetingBar
//

import SwiftUI

/// Meeting rooms booked for an event, shown as light grey chips.
struct RoomChipsView: View {
    let rooms: [String]
    var leading: CGFloat = 12
    /// Filled teal pill, like Join, for where to go next.
    var prominent = false
    /// Location rather than a booked room.
    var isLocation = false

    static let height: CGFloat = 26

    var body: some View {
        HStack(spacing: 6) {
            ForEach(rooms, id: \.self) { room in
                HStack(spacing: 4) {
                    Image(systemName: isLocation ? "mappin.and.ellipse" : "door.left.hand.open")
                        .font(.system(size: prominent ? 11 : 10, weight: prominent ? .semibold : .regular))
                    Text(room)
                        .font(prominent ? .system(size: 12, weight: .semibold) : .caption)
                        .lineLimit(1)
                }
                .foregroundStyle(prominent ? AnyShapeStyle(Color.white) : AnyShapeStyle(.secondary))
                .padding(.horizontal, prominent ? 12 : 8)
                .padding(.vertical, prominent ? 4 : 3)
                .background(Capsule().fill(prominent ? Color(nsColor: .systemTeal) : Color.primary.opacity(0.08)))
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, leading)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, minHeight: Self.height, alignment: .leading)
    }
}
