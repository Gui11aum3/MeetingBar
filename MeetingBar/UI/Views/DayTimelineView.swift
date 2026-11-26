//
//  DayTimelineView.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 22.05.2025.
//  Copyright © 2025 Andrii Leitsius. All rights reserved.
//

import SwiftUI

struct DaySegment: Identifiable {
    let id: String
    let start: Date
    let end: Date
    let color: Color
    let isHighlighted: Bool
    let title: String?

    init(
        id: String = UUID().uuidString,
        start: Date,
        end: Date,
        color: Color,
        isHighlighted: Bool = false,
        title: String? = nil
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.color = color
        self.isHighlighted = isHighlighted
        self.title = title
    }
}

enum DayTimelineLayout {
    /// How many hours are visible to the left / right of “now”
    static let hoursBefore: TimeInterval = 3 * 3600   // 3 h
    static let hoursAfter: TimeInterval = 6 * 3600   // 6 h

    static let baseTrackHeight: CGFloat = 22
    static let segmentHeight: CGFloat = 10
    static let rowSpacing: CGFloat = 4

    static var rowHeight: CGFloat { segmentHeight + rowSpacing }
}

struct DayTimelineLayoutCalculator {
    // MARK: Cached range information
    let now: Date
    let visibleRange: ClosedRange<Date>
    private let totalSeconds: TimeInterval

    init(now: Date = Date()) {
        self.now = now
        let lower = now.addingTimeInterval(-DayTimelineLayout.hoursBefore)
        let upper = now.addingTimeInterval( DayTimelineLayout.hoursAfter)
        self.visibleRange = lower...upper
        self.totalSeconds = upper.timeIntervalSince(lower)
    }

    // MARK: X-position helpers
    func xPosition(of date: Date, width: CGFloat) -> CGFloat {
        let clamped = min(max(date, visibleRange.lowerBound), visibleRange.upperBound)
        let seconds = clamped.timeIntervalSince(visibleRange.lowerBound)
        return width * CGFloat(seconds / totalSeconds)
    }

    // MARK: Hour ticks
    func hourTicks() -> [Date] {
        var out: [Date] = []
        var current = Calendar.current.nextDate(
            after: visibleRange.lowerBound.addingTimeInterval(-1),
            matching: DateComponents(minute: 0, second: 0),
            matchingPolicy: .strict
        )!
        while current <= visibleRange.upperBound {
            out.append(current)
            current = Calendar.current.date(byAdding: .hour, value: 1, to: current)!
        }
        return out
    }

    // MARK: Row packing
    func rows(for segments: [DaySegment]) -> [[DaySegment]] {
        var rows: [[DaySegment]] = []
        for seg in segments where seg.end > visibleRange.lowerBound && seg.start < visibleRange.upperBound {
            if let idx = rows.firstIndex(where: { row in
                !row.contains(where: { $0.start < seg.end && $0.end > seg.start })
            }) {
                rows[idx].append(seg)
            } else {
                rows.append([seg])
            }
        }
        return rows
    }
}

struct DayRelativeTimelineView: View {
    let segments: [DaySegment]
    let currentDate: Date
    let timeFormat: TimeFormat

    // Cached / pre-computed values
    private let layout: DayTimelineLayoutCalculator
    private let eventRows: [[DaySegment]]
    private let contentHeight: CGFloat

    /// Height the parent can rely on for sizing
    var preferredHeight: CGFloat { contentHeight + 26 }   // top labels + vertical padding

    // MARK: Init
    init(segments: [DaySegment], currentDate: Date, timeFormat: TimeFormat) {
        let layout = DayTimelineLayoutCalculator(now: currentDate)
        self.segments     = segments
        self.currentDate  = currentDate
        self.timeFormat   = timeFormat
        self.layout       = layout
        self.eventRows    = layout.rows(for: segments)
        self.contentHeight = DayTimelineLayout.baseTrackHeight +
            DayTimelineLayout.rowHeight * CGFloat(max(eventRows.count - 1, 0))
    }

    // MARK: Body
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            ZStack(alignment: .topLeading) {

                // One thin track the meetings sit on.
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: width, height: 4)
                    .offset(y: (DayTimelineLayout.baseTrackHeight - 4) / 2)

                // Free stretches of 30 min or more ahead of now, lightly
                // striped, so "free from" is visible at a glance.
                ForEach(Array(freeGaps.enumerated()), id: \.offset) { _, gap in
                    let startX = layout.xPosition(of: gap.lowerBound, width: width)
                    let endX = layout.xPosition(of: gap.upperBound, width: width)
                    FreeStripes()
                        .fill(Color.primary.opacity(0.07))
                        .frame(width: max(endX - startX, 0), height: DayTimelineLayout.segmentHeight)
                        .clipShape(Capsule())
                        .offset(x: startX, y: (DayTimelineLayout.baseTrackHeight - DayTimelineLayout.segmentHeight) / 2)
                }

                // Hour grid: faint ticks, muted labels. Labels too close to
                // an edge are skipped so they never get clipped.
                ForEach(layout.hourTicks(), id: \.self) { tick in
                    let x = layout.xPosition(of: tick, width: width)
                    Path { path in
                        path.move(to: CGPoint(x: x, y: 2))
                        path.addLine(to: CGPoint(x: x, y: contentHeight - 2))
                    }
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)

                    if x >= Self.labelEdgeInset, x <= width - Self.labelEdgeInset {
                        Text(hourFormatter.string(from: tick))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .position(x: x, y: -8)
                    }
                }

                // Event rows
                ForEach(eventRows.indices, id: \.self) { row in
                    ForEach(eventRows[row]) { seg in
                        let startX  = layout.xPosition(of: max(seg.start, layout.visibleRange.lowerBound), width: width)
                        let endX    = layout.xPosition(of: min(seg.end, layout.visibleRange.upperBound), width: width)
                        let widthPx = max(endX - startX, DayTimelineLayout.segmentHeight / 2)

                        // Solid meeting colour, no outline; the featured
                        // meeting is full strength, the rest a little lighter.
                        Capsule()
                            .fill(seg.color.opacity(seg.isHighlighted ? 1 : 0.6))
                            .frame(width: widthPx, height: DayTimelineLayout.segmentHeight)
                            .offset(
                                x: startX,
                                y: (DayTimelineLayout.baseTrackHeight - DayTimelineLayout.segmentHeight) / 2 +
                                   CGFloat(row) * DayTimelineLayout.rowHeight
                            )
                            .help(seg.title ?? "")
                    }
                }

                // Current time indicator
                if layout.visibleRange.contains(currentDate) {
                    let x = layout.xPosition(of: currentDate, width: width)
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 2, height: contentHeight + 4)
                        .offset(x: x - 1, y: -2)
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                        .offset(x: x - 3, y: -5)
                }
            }
            .frame(height: contentHeight)
            .padding(.top, 10)
            .padding(.vertical, 8)
            .padding(.horizontal, 17)
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("timeline_accessibility_label".loco(segments.count))
    }

    /// Gaps of at least 30 minutes between now and the end of the view.
    private var freeGaps: [ClosedRange<Date>] {
        let minimum: TimeInterval = 30 * 60
        let busy = segments.sorted { $0.start < $1.start }
        var cursor = max(currentDate, layout.visibleRange.lowerBound)
        var gaps: [ClosedRange<Date>] = []
        for seg in busy where seg.end > cursor {
            if seg.start.timeIntervalSince(cursor) >= minimum {
                gaps.append(cursor...seg.start)
            }
            cursor = max(cursor, seg.end)
        }
        let end = layout.visibleRange.upperBound
        if end.timeIntervalSince(cursor) >= minimum {
            gaps.append(cursor...end)
        }
        return gaps
    }

    /// Half a label's width: closer than this to an edge, a label clips.
    private static let labelEdgeInset: CGFloat = 8

    private var hourFormatter: DateFormatter {
        let format = DateFormatter()
        format.locale = I18N.instance.locale
        switch timeFormat {
        case .am_pm:    format.dateFormat = "h a"
        case .military: format.dateFormat = "HH"
        }
        return format
    }
}

// MARK: — Preview

#Preview {
    let cal = Calendar.current
    let now = Date()
    let sampleSegments = [
        DaySegment(
            start: cal.date(byAdding: .hour, value: -2, to: now)!,
            end: cal.date(byAdding: .hour, value: -1, to: now)!,
            color: .blue
        ),
        DaySegment(
            start: cal.date(byAdding: .minute, value: -90, to: now)!,
            end: cal.date(byAdding: .minute, value: -30, to: now)!,
            color: .blue
        ),
        DaySegment(
            start: cal.date(byAdding: .minute, value: -90, to: now)!,
            end: cal.date(byAdding: .minute, value: 30, to: now)!,
            color: .blue
        ),
        DaySegment(
            start: cal.date(byAdding: .minute, value: -30, to: now)!,
            end: cal.date(byAdding: .minute, value: 30, to: now)!,
            color: .blue
        ),
        DaySegment(
            start: cal.date(byAdding: .hour, value: 1, to: now)!,
            end: cal.date(byAdding: .hour, value: 2, to: now)!,
            color: .green
        ),
        DaySegment(
            start: cal.date(byAdding: .hour, value: 4, to: now)!,
            end: cal.date(byAdding: .hour, value: 5, to: now)!,
            color: .orange
        )
    ]

    DayRelativeTimelineView(
        segments: sampleSegments,
        currentDate: now,
        timeFormat: .military
    )
    .padding()
}

/// Diagonal stripes for free time on the timeline.
private struct FreeStripes: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step: CGFloat = 4
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            path.addLine(to: CGPoint(x: x + rect.height + 1.5, y: rect.minY))
            path.addLine(to: CGPoint(x: x + 1.5, y: rect.maxY))
            path.closeSubpath()
            x += step
        }
        return path
    }
}
