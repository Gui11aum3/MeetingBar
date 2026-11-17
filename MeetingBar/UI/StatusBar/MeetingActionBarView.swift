//
//  MeetingActionBarView.swift
//  MeetingBar
//
//  One row of one-click actions for an opened meeting: Join, Yes / Maybe /
//  No, and a ⋯ marker for the rest. The menu item hosting this view carries
//  the remaining actions as its submenu, so hovering the row opens them to
//  the side like any native submenu.
//

import SwiftUI

struct MeetingActionBarView: View {
    let showsJoin: Bool
    let showsResponses: Bool
    var leading: CGFloat = 28
    var onJoin: () -> Void = {}
    var onRespond: (EventResponse) -> Void = { _ in }

    @State var response: EventResponse?

    static let height: CGFloat = 30

    var body: some View {
        HStack(spacing: 6) {
            if showsJoin {
                Button(action: onJoin) {
                    Text("status_bar_action_join".loco()).fontWeight(.semibold)
                }
                .buttonStyle(BarButtonStyle(kind: .primary))
            }
            if showsResponses {
                ForEach(Self.responses, id: \.0) { item in
                    Button {
                        response = item.0
                        onRespond(item.0)
                    } label: {
                        Text(item.1.loco())
                    }
                    .buttonStyle(BarButtonStyle(kind: response == item.0 ? .selected : .plain))
                    .accessibilityAddTraits(response == item.0 ? .isSelected : [])
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityLabel("status_bar_control_actions".loco())
        }
        .padding(.leading, leading)
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, minHeight: Self.height, alignment: .leading)
    }

    private static let responses: [(EventResponse, String)] = [
        (.accept, "status_bar_action_yes"),
        (.maybe, "status_bar_action_maybe"),
        (.decline, "status_bar_action_no")
    ]
}

private struct BarButtonStyle: ButtonStyle {
    enum Kind { case primary, selected, plain }
    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .foregroundStyle(foreground)
            .background(RoundedRectangle(cornerRadius: 6).fill(background))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(border))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
    }

    private var foreground: Color {
        switch kind {
        case .primary: .white
        case .selected: .accentColor
        case .plain: .primary
        }
    }

    private var background: Color {
        switch kind {
        case .primary: .accentColor
        case .selected: .accentColor.opacity(0.14)
        case .plain: Color.primary.opacity(0.05)
        }
    }

    private var border: Color {
        switch kind {
        case .primary: .clear
        case .selected: .accentColor.opacity(0.5)
        case .plain: Color.primary.opacity(0.12)
        }
    }
}
