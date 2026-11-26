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
                        .font(.system(size: 11, weight: prominent ? .medium : .regular))
                    Text(room)
                        .font(.system(size: 11, weight: prominent ? .medium : .regular))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 180, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(prominent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                // Light tint with coloured text reads in light and dark mode,
                // unlike white text on a bright fill.
                .background(RoundedRectangle(cornerRadius: 6).fill(
                    prominent ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.08)
                ))
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, leading)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, minHeight: Self.height, alignment: .leading)
    }
}
