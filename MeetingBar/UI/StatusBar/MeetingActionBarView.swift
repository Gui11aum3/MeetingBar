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
    /// Once answered, the three choices fold into one "✓ Going" pill;
    /// tapping it shows them again.
    @State private var isChoosing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                if let response, !isChoosing {
                    Button {
                        isChoosing = true
                    } label: {
                        Label(Self.answeredTitle(response).loco(), systemImage: "checkmark")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(BarButtonStyle(kind: .selected))
                    .accessibilityAddTraits(.isSelected)
                } else {
                    ForEach(Self.responses, id: \.0) { item in
                        Button {
                            // Strong ease-out, under 200 ms; none with Reduce Motion.
                            withAnimation(reduceMotion ? nil : .timingCurve(0.23, 1, 0.32, 1, duration: 0.18)) {
                                response = item.0
                                isChoosing = false
                            }
                            onRespond(item.0)
                        } label: {
                            // The current answer carries a checkmark, so it
                            // reads as chosen, not just slightly darker.
                            if response == item.0 {
                                Label(item.1.loco(), systemImage: "checkmark")
                                    .labelStyle(.titleAndIcon)
                                    .font(.system(size: 12, weight: .semibold))
                            } else {
                                Text(item.1.loco())
                            }
                        }
                        .buttonStyle(BarButtonStyle(kind: response == item.0 ? .selected : .plain))
                        .accessibilityAddTraits(response == item.0 ? .isSelected : [])
                    }
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

    private static func answeredTitle(_ response: EventResponse) -> String {
        switch response {
        case .accept: "status_bar_action_answered_yes"
        case .maybe: "status_bar_action_answered_maybe"
        case .decline: "status_bar_action_answered_no"
        }
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
        PressableLabel(configuration: configuration, kind: kind)
    }
}

/// Scales to 0.97 the moment it's pressed and tints on hover, so every
/// button answers before the click completes.
private struct PressableLabel: View {
    let configuration: ButtonStyleConfiguration
    let kind: BarButtonStyle.Kind
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(.system(size: 12))
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .foregroundStyle(foreground)
            .background(RoundedRectangle(cornerRadius: 6).fill(background))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(border))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
    }

    private var foreground: Color {
        switch kind {
        case .primary: .white
        case .selected: .primary
        case .plain: .primary
        }
    }

    private var background: Color {
        switch kind {
        case .primary: .accentColor
        case .selected: Color.primary.opacity(isHovered ? 0.20 : 0.16)
        case .plain: Color.primary.opacity(isHovered ? 0.09 : 0.05)
        }
    }

    private var border: Color {
        switch kind {
        case .primary: .clear
        case .selected: Color.primary.opacity(0.45)
        case .plain: Color.primary.opacity(0.12)
        }
    }
}
