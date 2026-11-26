//
//  MeetingSummaryView.swift
//  MeetingBar
//

import AppKit
import SwiftUI

struct MeetingSummaryPresentation: Equatable {
    let sectionTitle: String
    let eventTitle: String
    let metadata: [String]
    let meetingService: MeetingServices?
    /// Relative time until the meeting starts (e.g. "in 25m"); nil for
    /// running meetings, where the section title already says enough.
    var countdown: String?

    var metadataText: String {
        metadata.joined(separator: " · ")
    }

    var sectionTitleText: String {
        // "Starts in 1h 6m" says more than "Next meeting • in 1h 6m".
        guard let countdown, !countdown.isEmpty else { return sectionTitle }
        return countdown
    }
}

struct MeetingSummaryView: View {
    let presentation: MeetingSummaryPresentation
    let providerIcon: NSImage
    var onJoin: (() -> Void)?
    /// Global join shortcut, e.g. "⇧⌘D", shown inside the Join pill.
    var joinShortcut: String?
    /// false: only the metadata line and Join (expanded event-list rows).
    var showsHeader = true
    /// Shows ⋯ when the card itself opens the other actions.
    var showsMore = false
    /// 0…1 through a running meeting; nil for upcoming ones.
    var progress: Double?
    var accentColor: Color = .accentColor
    /// Up to four attendees' initials, plus how many more there are.
    var attendeeInitials: [String] = []
    var extraAttendees = 0

    @State private var isHovered = false
    /// Feedback on press-down, not on release.
    @State private var isPressed = false

    static let preferredWidth: CGFloat = 380
    static let preferredHeight: CGFloat = 76
    static let compactHeight: CGFloat = 30

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                if showsHeader {
                Text(presentation.sectionTitleText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 7) {
                    if providerIcon.size.width > 0 {
                        Image(nsImage: providerIcon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                    }

                    Text(presentation.eventTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                }

                HStack(spacing: 8) {
                    Text(presentation.metadataText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if showsHeader, !attendeeInitials.isEmpty {
                        AttendeeFaces(initials: attendeeInitials, extra: extraAttendees)
                    }
                }

                // How far through the meeting you are, in its colour.
                if showsHeader, let progress {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule().fill(accentColor)
                                .frame(width: proxy.size.width * min(max(progress, 0), 1))
                        }
                    }
                    .frame(height: 3)
                    .padding(.top, 3)
                }
            }

            if onJoin != nil {
                Spacer(minLength: 8)
                (Text("notifications_meetingbar_join_event_action".loco())
                    + Text(joinShortcut.map { "  \($0)" } ?? "").fontWeight(.medium).foregroundColor(.white.opacity(0.75)))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor))
                    .opacity(isHovered ? 1.0 : 0.9)
                    .scaleEffect(isPressed ? 0.97 : 1)
                    .animation(.easeOut(duration: 0.1), value: isPressed)
            }
            if showsMore {
                if onJoin == nil { Spacer(minLength: 8) }
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("status_bar_control_actions".loco())
            }
        }
        .padding(.leading, showsHeader ? 17 : 28)
        .padding(.trailing, 12)
        .padding(.vertical, showsHeader ? 6 : 2)
        .frame(
            maxWidth: .infinity,
            minHeight: showsHeader ? Self.preferredHeight : Self.compactHeight,
            alignment: .leading
        )
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered && onJoin != nil ? Color.primary.opacity(0.06) : Color.clear)
        )
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            guard onJoin != nil else { return }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if onJoin != nil, !isPressed { isPressed = true } }
                .onEnded { _ in isPressed = false }
        )
        .onTapGesture { onJoin?() }
    }
}

#Preview {
    MeetingSummaryView(
        presentation: MeetingSummaryPresentation(
            sectionTitle: "Next meeting",
            eventTitle: "Weekly product sync",
            metadata: ["10:00 – 10:30", "Zoom", "Work"],
            meetingService: .zoom,
            countdown: "in 25m"
        ),
        providerIcon: getIconForMeetingService(.zoom),
        onJoin: {}
    )
}

/// Small overlapping initials circles, like a calendar's attendee row.
private struct AttendeeFaces: View {
    let initials: [String]
    let extra: Int

    var body: some View {
        HStack(spacing: -4) {
            ForEach(Array(initials.enumerated()), id: \.offset) { _, text in
                Text(text)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color(nsColor: .controlBackgroundColor)))
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
            }
            if extra > 0 {
                Text("+\(extra)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
            }
        }
        .accessibilityHidden(true)
    }
}
