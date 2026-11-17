//
//  MenuBuilder.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 28.05.2025.
//  Copyright © 2025 Andrii Leitsius. All rights reserved.
//

import Cocoa
import KeyboardShortcuts
import SwiftUI

@MainActor
struct MenuBuilder {
    static let timelineItemIdentifier = NSUserInterfaceItemIdentifier(
        "MeetingBar.StatusBar.Timeline"
    )
    static let meetingSummaryItemIdentifier = NSUserInterfaceItemIdentifier(
        "MeetingBar.StatusBar.MeetingSummary"
    )

    /// All menu items created will forward their action to this object.
    let target: AnyObject
    /// Snapshot of all events, settings, and pre-computed flags used while
    /// building this menu. Replaces direct `Defaults` reads.
    /// Defaults to a zero-state snapshot for tests that don't exercise
    /// state-driven branches; production callers must pass a real snapshot.
    var state: StatusBarMenuState = StatusBarMenuState()
    var isFantasticalInstalled = checkIsFantasticalInstalled()
    var installationDate: Date?
    var now: Date = Date()
    /// Upcoming events the user clicked open in the event list.
    var expandedEventIDs: Set<String> = []
    /// Leave the featured meeting out of the event list (it has its own card).
    var hidesFeaturedEventInList = false
    /// Day summary layout: "N meetings left" header, ▸/• glyph column,
    /// "Updated" footer, and no Rate app row (it lives in Preferences).
    var usesDaySummaryLayout = false
    /// Rooms / location as chips; `.off` keeps the raw grey room chips.
    var placeChipMode: MeetingPlaceChipMode = .off
    /// Google working location per day, from `MeetingPlacePolicy.dayKey`.
    var workingLocationsByDay: [String: WorkingLocationKind] = [:]

    // MARK: Top section ------------------------------------------------------

    func buildTopSection() -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        if let timelineItem = makeTimelineItem() {
            items.append(timelineItem)
        }
        items.append(contentsOf: buildMeetingControlSection())
        items.append(.separator())
        return items
    }

    // MARK: Meeting control section ------------------------------------------

    private func isHappeningNow(_ event: MBEvent) -> Bool {
        event.startDate <= now && event.endDate > now
    }

    /// The meeting happening now: the selected next event when it has
    /// started, otherwise the first ongoing timed meeting you haven't declined
    /// (next-event selection can skip ones without a link or hand off early).
    var currentMeeting: MBEvent? {
        if let next = state.nextEvent, isHappeningNow(next) { return next }
        return state.todayEvents
            .filter {
                isHappeningNow($0) && !$0.isAllDay && shouldRenderEvent($0)
                    && $0.participationStatus != .declined && $0.status != .canceled
            }
            .min { $0.startDate < $1.startDate }
    }

    /// The event shown in the card at the top, if any.
    private var featuredEventID: String? {
        usesDaySummaryLayout ? currentMeeting?.id : state.nextEvent?.id
    }

    func buildMeetingControlSection() -> [NSMenuItem] {
        if usesDaySummaryLayout {
            // The card is only for the meeting happening now; upcoming
            // meetings stay in the list below, where they expand.
            if let event = currentMeeting {
                return buildMeetingControlSection(event: event)
            }
            if state.nextEvent != nil || !state.todayEvents.isEmpty { return buildProviderWarningItems() }
        } else if let event = state.nextEvent {
            return buildMeetingControlSection(event: event)
        }
        // emptyStateReason does not propagate .stale, so when the provider is
        // stale and the only reason for an empty section is that there are no
        // upcoming meetings, replace the generic message with the stale warning.
        if state.providerWarning == .stale,
           state.emptyStateReason == .noUpcomingMeetings || state.emptyStateReason == nil {
            return buildProviderWarningItems()
        }
        return buildEmptyMeetingControlSection()
    }

    private func buildMeetingControlSection(event: MBEvent) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        items.append(makeMeetingSummaryItem(for: event))
        items.append(contentsOf: makeRoomChipsItem(for: event, leading: 12, prominent: true).map { [$0] } ?? [])
        items.append(contentsOf: makeFeaturedDocumentItems(for: event))
        // The card already has Join; the bar adds the answer and the rest.
        items.append(makeActionBarItem(for: event, showsJoin: false, leading: 15))
        items.append(contentsOf: buildProviderWarningItems())
        return items
    }

    func meetingSummaryPresentation(for event: MBEvent) -> MeetingSummaryPresentation {
        let isCurrent = event.startDate <= now && event.endDate > now
        let eventTitle = event.title.isEmpty
            ? "status_bar_no_title".loco()
            : event.title
        let time = eventTimePresentation(for: event)
        let timeRange = event.isAllDay
            ? time.start
            : "\(time.start) – \(time.end)"
        let meetingProvider = event.meetingLink?.service
            .flatMap(MeetingProvider.provider(for:))?
            .displayName
        // The account (source/email) is the same for nearly every event, so
        // it's noise here; the calendar name is kept only when it says
        // something other than an address.
        let calendarName = event.calendar.title.contains("@") ? nil : event.calendar.title

        let countdown: String?
        if isCurrent || event.isAllDay {
            countdown = nil
        } else {
            let timeLeft = StatusBarTitlePolicy.formattedTimeLeft(
                from: now,
                to: event.startDate,
                calendar: Calendar.current
            )
            countdown = timeLeft.isEmpty ? nil : "status_bar_control_starts_in".loco(timeLeft)
        }

        return MeetingSummaryPresentation(
            sectionTitle: isCurrent
                ? "status_bar_control_now".loco()
                : "status_bar_control_next_meeting".loco(),
            eventTitle: eventTitle,
            metadata: uniqueMetadataValues([
                timeRange,
                meetingProvider,
                calendarName
            ]),
            meetingService: event.meetingLink?.service,
            countdown: countdown
        )
    }

    private func buildProviderWarningItems() -> [NSMenuItem] {
        guard let warning = state.providerWarning else { return [] }

        let title: String
        let actionTitle: String
        let action: Selector

        switch warning {
        case .authRequired:
            title = "status_bar_control_auth_required".loco()
            actionTitle = "status_bar_control_reconnect".loco()
            action = #selector(StatusBarItemController.reconnectProviderAction)
        case .permissionRequired:
            title = "status_bar_control_permission_required".loco()
            actionTitle = "status_bar_control_grant_permission".loco()
            action = #selector(StatusBarItemController.openCalendarPermissionsAction)
        case .stale:
            title = "status_bar_control_stale".loco()
            actionTitle = "status_bar_section_refresh_sources".loco()
            action = #selector(StatusBarItemController.handleManualRefresh)
        case .refreshFailed:
            title = "status_bar_control_refresh_failed".loco()
            actionTitle = "status_bar_section_refresh_sources".loco()
            action = #selector(StatusBarItemController.handleManualRefresh)
        }

        let actionItem = NSMenuItem(title: actionTitle, action: action, keyEquivalent: "")
        actionItem.target = target
        return [statusItem(title: title), actionItem]
    }

    private func makeMeetingActionsItem(for event: MBEvent) -> NSMenuItem {
        let title = "status_bar_control_actions".loco()
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        // Visually secondary so it doesn't compete with the summary card above.
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: MenuStyleConstants.defaultFontSize - 1),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        let menu = NSMenu(title: title)
        addEventActions(to: menu, event: event)
        item.submenu = menu
        return item
    }

    private func buildEmptyMeetingControlSection() -> [NSMenuItem] {
        let reason = state.emptyStateReason ?? .noUpcomingMeetings
        let title: String
        let actionTitle: String
        let action: Selector

        switch reason {
        case .authRequired:
            title = "status_bar_control_auth_required".loco()
            actionTitle = "status_bar_control_reconnect".loco()
            action = #selector(StatusBarItemController.reconnectProviderAction)
        case .permissionRequired:
            title = "status_bar_control_permission_required".loco()
            actionTitle = "status_bar_control_grant_permission".loco()
            action = #selector(StatusBarItemController.openCalendarPermissionsAction)
        case .noCalendarsSelected:
            title = "status_bar_control_no_calendars".loco()
            actionTitle = "status_bar_control_select_calendars".loco()
            action = #selector(StatusBarItemController.openPreferencesAction)
        case .refreshFailed:
            title = "status_bar_control_refresh_failed".loco()
            actionTitle = "status_bar_section_refresh_sources".loco()
            action = #selector(StatusBarItemController.handleManualRefresh)
        case .noUpcomingMeetings:
            title = "status_bar_control_no_upcoming".loco()
            actionTitle = "status_bar_section_refresh_sources".loco()
            action = #selector(StatusBarItemController.handleManualRefresh)
        }

        let titleItem = statusItem(title: title, bold: true)
        let actionItem = NSMenuItem(title: actionTitle, action: action, keyEquivalent: "")
        actionItem.target = target
        return [titleItem, actionItem]
    }

    private func statusItem(title: String, bold: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        if bold {
            item.attributedTitle = NSAttributedString(
                string: title,
                attributes: [.font: NSFont.boldSystemFont(ofSize: MenuStyleConstants.defaultFontSize)]
            )
        }
        item.isEnabled = false
        return item
    }

    private func makeTimelineItem() -> NSMenuItem? {
        guard state.shouldShowTimeline else { return nil }

        let today = Calendar.current.startOfDay(for: now)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let highlightedEventID = state.nextEvent?.id
        let segments = state.todayEvents.compactMap { event -> DaySegment? in
            guard shouldRenderEvent(event) else { return nil }
            return DaySegment(
                id: event.id,
                start: max(event.startDate, today),
                end: min(event.endDate, tomorrow),
                color: Color(event.displayColor),
                isHighlighted: event.id == highlightedEventID,
                title: event.title
            )
        }
        let timeline = DayRelativeTimelineView(
            segments: segments,
            currentDate: now,
            timeFormat: state.timeFormat
        )
        let hosting = NSHostingView(rootView: timeline)
        hosting.autoresizingMask = [.width]
        hosting.frame = NSRect(
            x: 0,
            y: 0,
            width: MeetingSummaryView.preferredWidth,
            height: timeline.preferredHeight
        )

        let item = NSMenuItem()
        item.identifier = Self.timelineItemIdentifier
        item.view = hosting
        return item
    }

    private func makeMeetingSummaryItem(for event: MBEvent) -> NSMenuItem {
        let item = NSMenuItem()
        item.identifier = Self.meetingSummaryItemIdentifier
        item.representedObject = event

        let onJoin: (() -> Void)?
        if event.meetingLink != nil, let controller = target as? StatusBarItemController {
            onJoin = { [weak item, weak controller] in
                guard let item, let controller else { return }
                item.menu?.cancelTracking()
                controller.joinEvent(sender: item)
            }
        } else {
            onJoin = nil
        }

        let presentation = meetingSummaryPresentation(for: event)
        let summary = MeetingSummaryView(
            presentation: presentation,
            providerIcon: getIconForMeetingService(presentation.meetingService),
            onJoin: onJoin,
            joinShortcut: KeyboardShortcuts.getShortcut(for: .joinEventShortcut)?.description
        )
        let hosting = NSHostingView(rootView: summary)
        hosting.frame = NSRect(
            x: 0,
            y: 0,
            width: MeetingSummaryView.preferredWidth,
            height: MeetingSummaryView.preferredHeight
        )
        hosting.autoresizingMask = [.width]
        item.view = hosting
        return item
    }

    private func firstMeaningfulMetadataValue(_ values: [String?]) -> String? {
        values.lazy
            .compactMap { value in
                value?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .first { !$0.isEmpty }
    }

    private func uniqueMetadataValues(_ values: [String?]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty
            else { return nil }
            let identity = trimmed.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            guard seen.insert(identity).inserted else { return nil }
            return trimmed
        }
    }

    // MARK: Date section ------------------------------------------------------

    func buildDateSection(
        date: Date,
        title: String,
        events: [MBEvent],
        subdueEmptyState: Bool = false
    ) -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        // Header
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "E, d MMM"
        dateFormatter.locale = I18N.instance.locale

        let dateString = dateFormatter.string(from: date)
        let dateTitle = "\(title) (\(dateString))"
        let titleItem: NSMenuItem
        if usesDaySummaryLayout {
            // Notion-style: the day name alone, small and grey.
            titleItem = Self.dayLabelItem(title)
        } else if #available(macOS 14.0, *) {
            titleItem = NSMenuItem.sectionHeader(title: dateTitle)
        } else {
            titleItem = NSMenuItem(title: dateTitle, action: nil, keyEquivalent: "")
            titleItem.attributedTitle = NSAttributedString(
                string: dateTitle,
                attributes: [
                    .font: NSFont.systemFont(
                        ofSize: MenuStyleConstants.defaultFontSize - 2,
                        weight: .semibold
                    ),
                    .foregroundColor: NSColor.secondaryLabelColor
                ])
            titleItem.isEnabled = false
        }

        items.append(titleItem)
        if usesDaySummaryLayout, Calendar.current.isDate(date, inSameDayAs: now) {
            items.append(makeDaySummaryHeader(events: events))
        }

        // Events
        // The featured meeting already has its own card at the top.
        let sortedEvents = events
            .filter { !hidesFeaturedEventInList || $0.id != featuredEventID }
            .sorted { $0.startDate < $1.startDate }
        if sortedEvents.isEmpty {
            let item = NSMenuItem(
                title: "status_bar_section_date_nothing".loco(title.lowercased()),
                action: nil,
                keyEquivalent: ""
            )
            item.isEnabled = false
            if subdueEmptyState {
                item.attributedTitle = NSAttributedString(
                    string: item.title,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: MenuStyleConstants.defaultFontSize - 1),
                        .foregroundColor: NSColor.disabledControlTextColor
                    ]
                )
            }
            items.append(item)
        }
        for event in sortedEvents {
            if let item = makeEventItem(event) {
                items.append(item)
                let expandable = item.submenu == nil && Self.isExpandable(event, now: now)
                if usesDaySummaryLayout {
                    Self.prependParticipationBar(to: item, event: event)
                }
                if expandable {
                    items.append(contentsOf: makeExpandableRow(item, event: event))
                } else {
                    items.append(contentsOf: makeExpandedDocumentItems(for: event))
                }
            }
        }

        return items
    }

    // MARK: Day summary -------------------------------------------------------

    private static let glyphColumnWidth: CGFloat = 14

    enum ParticipationBarStyle: Equatable {
        case filled, striped, hollow
    }

    /// Notion-Calendar-style bar: filled = going, striped = maybe,
    /// hollow = declined or not answered yet.
    static func participationBarStyle(for event: MBEvent) -> ParticipationBarStyle {
        switch event.participationStatus {
        case .tentative: return .striped
        case .declined, .pending: return .hollow
        default: return event.status == .canceled ? .hollow : .filled
        }
    }

    static func participationBar(style: ParticipationBarStyle, color: NSColor) -> NSImage {
        let size = NSSize(width: 4, height: 15)
        return NSImage(size: size, flipped: false) { rect in
            let bar = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 1.5, yRadius: 1.5)
            switch style {
            case .filled:
                color.setFill()
                bar.fill()
            case .striped:
                NSGraphicsContext.saveGraphicsState()
                bar.addClip()
                color.withAlphaComponent(0.3).setFill()
                rect.fill()
                color.setStroke()
                let stripes = NSBezierPath()
                stripes.lineWidth = 1.4
                var y: CGFloat = -rect.width
                while y < rect.height {
                    stripes.move(to: NSPoint(x: 0, y: y))
                    stripes.line(to: NSPoint(x: rect.width, y: y + rect.width))
                    y += 3.5
                }
                stripes.stroke()
                NSGraphicsContext.restoreGraphicsState()
            case .hollow:
                color.setStroke()
                bar.lineWidth = 1
                bar.stroke()
            }
            return true
        }
    }

    struct DaySummary: Equatable {
        let meetingsLeft: Int
        let freeFrom: Date?
    }

    /// Timed meetings you're still going to (not declined or cancelled) that
    /// haven't ended, and when the last of them ends.
    static func daySummary(events: [MBEvent], now: Date) -> DaySummary {
        let left = events.filter {
            !$0.isAllDay && $0.endDate > now
                && $0.participationStatus != .declined && $0.status != .canceled
        }
        return DaySummary(meetingsLeft: left.count, freeFrom: left.map(\.endDate).max())
    }

    /// The day title ("Today", "Tomorrow"), bold and black.
    static func dayLabelItem(_ title: String) -> NSMenuItem {
        labelItem(
            title,
            font: NSFont.systemFont(ofSize: MenuStyleConstants.defaultFontSize + 2, weight: .semibold),
            color: .labelColor
        )
    }

    /// A text row drawn by a plain label view so the menu doesn't grey it out
    /// like a disabled row.
    static func labelItem(_ text: String, font: NSFont, color: NSColor) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        label.sizeToFit()
        let height = ceil(label.frame.height) + 6
        let container = NSView(frame: NSRect(x: 0, y: 0, width: label.frame.width + 28, height: height))
        label.frame.origin = NSPoint(x: 14, y: 2)
        container.addSubview(label)
        container.autoresizingMask = [.width]
        item.view = container
        item.isEnabled = false
        return item
    }

    /// "3 left · free from 16:00", a grey subtitle under the "Today" title.
    private func makeDaySummaryHeader(events: [MBEvent]) -> NSMenuItem {
        let summary = Self.daySummary(
            events: events.filter { shouldRenderEvent($0) }, now: now)
        var text: String
        switch summary.meetingsLeft {
        case 0: text = "status_bar_day_summary_none".loco()
        case 1: text = "status_bar_day_summary_one".loco()
        default: text = "status_bar_day_summary_many".loco(summary.meetingsLeft)
        }
        if let freeFrom = summary.freeFrom {
            let formatter = DateFormatter()
            formatter.locale = I18N.instance.locale
            formatter.dateFormat = state.timeFormat == .am_pm ? "h:mm a" : "HH:mm"
            text += " · " + "status_bar_day_summary_free_from".loco(formatter.string(from: freeFrom))
        }

        // Subtitle under the day title: small and grey.
        return Self.labelItem(
            text,
            font: NSFont.systemFont(ofSize: MenuStyleConstants.defaultFontSize - 1),
            color: .secondaryLabelColor
        )
    }

    /// Adds the participation bar column in front of an event row's time.
    static func prependParticipationBar(to item: NSMenuItem, event: MBEvent) {
        let original = item.attributedTitle ?? NSAttributedString(string: item.title)
        let text = NSMutableAttributedString(attributedString: original)
        let column = glyphColumnWidth
        text.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle else { return }
            style.tabStops = [NSTextTab(textAlignment: .left, location: column)]
                + style.tabStops.map { NSTextTab(textAlignment: $0.alignment, location: $0.location + column) }
            text.addAttribute(.paragraphStyle, value: style, range: range)
        }
        let attachment = NSTextAttachment()
        let style = participationBarStyle(for: event)
        attachment.image = participationBar(style: style, color: event.displayColor)
        attachment.bounds = NSRect(x: 0, y: -2.5, width: 4, height: 15)
        let bar = NSMutableAttributedString(attachment: attachment)
        bar.append(NSAttributedString(string: "\t"))
        if text.length > 0, let paragraph = text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) {
            bar.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: bar.length))
        }
        text.insert(bar, at: 0)
        item.attributedTitle = text
    }

    /// "Updated 3 min ago", or an orange "Offline" line when refresh fails.
    func buildUpdatedFooter() -> NSMenuItem? {
        guard usesDaySummaryLayout else { return nil }
        let lastRefresh: Date?
        let offline: Bool
        switch state.providerStatus {
        case .connected(let date): lastRefresh = date; offline = false
        case .stale(let date, _): lastRefresh = date; offline = true
        case .refreshFailed: lastRefresh = state.providerHealth.lastSuccessfulRefresh; offline = true
        default: return nil
        }
        var text: String
        if let lastRefresh {
            let minutes = max(0, Int(now.timeIntervalSince(lastRefresh) / 60))
            text = minutes < 1
                ? "status_bar_footer_updated_now".loco()
                : "status_bar_footer_updated_minutes".loco(minutes)
        } else {
            text = ""
        }
        if offline {
            text = text.isEmpty
                ? "status_bar_footer_offline".loco()
                : "status_bar_footer_offline".loco() + " · " + text
        }
        guard !text.isEmpty else { return nil }
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: MenuStyleConstants.defaultFontSize - 2),
            .foregroundColor: offline ? NSColor.systemOrange : NSColor.tertiaryLabelColor
        ])
        item.isEnabled = false
        return item
    }

    // MARK: Join section ------------------------------------------------------

    func buildJoinSection(
        nextEvent: MBEvent?,
        includeJoinAction: Bool = true
    ) -> [NSMenuItem] {

        var items: [NSMenuItem] = []

        // MENU ITEM: Join the meeting
        let now = self.now

        if let nextEvent = nextEvent, includeJoinAction {
            let itemTitle =
                nextEvent.startDate < now
                ? "status_bar_section_join_current_meeting".loco()
                : "status_bar_section_join_next_meeting".loco()

            let joinItem = NSMenuItem(
                title: itemTitle,
                action: #selector(StatusBarItemController.joinNextMeeting),
                keyEquivalent: ""
            )
            joinItem.target = target
            items.append(joinItem)

            if let alternateLinksItem = makeAlternateMeetingLinksMenu(for: nextEvent) {
                items.append(alternateLinksItem)
            }
        }

        // MENU ITEM: Create meeting
        let createEventItem = NSMenuItem(
            title: "status_bar_section_join_create_meeting".loco(),
            action: #selector(StatusBarItemController.createMeetingAction),
            keyEquivalent: ""
        )
        createEventItem.target = target
        // Use the non-observing overload: `setShortcut(for:)` registers a
        // NotificationCenter observer that retains the item forever, and this menu
        // is rebuilt every minute, so a newly recorded shortcut still shows up.
        createEventItem.setShortcut(KeyboardShortcuts.getShortcut(for: .createMeetingShortcut))
        items.append(createEventItem)

        // MENU ITEM: Quick actions menu
        let quickActionsItem = NSMenuItem(
            title: "status_bar_quick_actions".loco(),
            action: nil,
            keyEquivalent: ""
        )
        quickActionsItem.isEnabled = true
        let quickActionsSubmenu = NSMenu(title: "status_bar_quick_actions".loco())
        quickActionsItem.submenu = quickActionsSubmenu
        items.append(quickActionsItem)

        // MENU ITEM: QUICK ACTIONS: Dismiss meeting
        if let nextEvent = nextEvent {
            let itemTitle =
                nextEvent.startDate < now
                ? "status_bar_menu_dismiss_curent_meeting".loco()
                : "status_bar_menu_dismiss_next_meeting".loco()

            let dismissMeetingItem = quickActionsSubmenu.addItem(
                withTitle: itemTitle,
                action: #selector(StatusBarItemController.dismissNextMeetingAction),
                keyEquivalent: ""
            )
            dismissMeetingItem.target = target
        }

        if !state.events.dismissedEvents.isEmpty {
            let undiDismissMeetingsItem = quickActionsSubmenu.addItem(
                withTitle: "status_bar_menu_remove_all_dismissals".loco(),
                action: #selector(StatusBarItemController.undismissMeetingsActions),
                keyEquivalent: ""
            )
            undiDismissMeetingsItem.target = target
        }

        // MENU ITEM: QUICK ACTIONS: Open link from clipboard
        let openLinkFromClipboardItem = quickActionsSubmenu.addItem(
            withTitle: "status_bar_section_join_from_clipboard".loco(),
            action: #selector(StatusBarItemController.openLinkFromClipboardAction),
            keyEquivalent: ""
        )
        openLinkFromClipboardItem.target = target
        openLinkFromClipboardItem.setShortcut(KeyboardShortcuts.getShortcut(for: .openClipboardShortcut))

        // MENU ITEM: QUICK ACTIONS: Toggle meeting name visibility
        if state.statusBar.eventTitleFormat == .show
            || state.statusBar.eventTitleFormat == .generic {
            let title =
                state.statusBar.eventTitleFormat == .generic
                ? "status_bar_show_meeting_names".loco()
                : "status_bar_hide_meeting_names".loco()

            let toggleMeetingTitleVisibilityItem = quickActionsSubmenu.addItem(
                withTitle: title,
                action: #selector(StatusBarItemController.toggleMeetingTitleVisibility),
                keyEquivalent: ""
            )
            toggleMeetingTitleVisibilityItem.setShortcut(KeyboardShortcuts.getShortcut(for: .toggleMeetingTitleVisibilityShortcut))
            toggleMeetingTitleVisibilityItem.target = target
        }

        // MENU ITEM: QUICK ACTIONS: Refresh sources
        let refrsehItem = quickActionsSubmenu.addItem(
            withTitle: "status_bar_section_refresh_sources".loco(),
            action: #selector(StatusBarItemController.handleManualRefresh),
            keyEquivalent: ""
        )
        refrsehItem.target = target

        return items
    }

    // MARK: Preferences section -----------------------------------------------

    func buildPreferencesSection() -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        let showChangelogItem = compareVersions(
            state.appMajorVersion, state.lastRevisedMajorVersion)

        if showChangelogItem {
            let changelogItem = NSMenuItem(
                title: "status_bar_whats_new".loco(),
                action: #selector(StatusBarItemController.openChangelogAction),
                keyEquivalent: ""
            )
            changelogItem.image = NSImage(named: NSImage.statusAvailableName)
            changelogItem.target = target
            items.append(changelogItem)
        }

        var showRateAppButton = true
        if let installationDate {
            let twoWeeksAfterInstallation = Calendar.current.date(
                byAdding: .day,
                value: 14,
                to: installationDate
            )!
            showRateAppButton = now > twoWeeksAfterInstallation
        }

        if showRateAppButton, !usesDaySummaryLayout {
            let rateItem = NSMenuItem(
                title: "status_bar_rate_app".loco(),
                action: #selector(StatusBarItemController.rateApp),
                keyEquivalent: ""
            )
            rateItem.target = target
            items.append(rateItem)
        }

        let preferencesItem = NSMenuItem(
            title: "\("status_bar_preferences".loco())…",
            action: #selector(StatusBarItemController.openPreferencesAction),
            keyEquivalent: ","
        )
        preferencesItem.target = target
        items.append(preferencesItem)

        let quitItem = NSMenuItem(
            title: "status_bar_quit".loco(),
            action: #selector(StatusBarItemController.quitAction),
            keyEquivalent: "q"
        )
        quitItem.target = target
        items.append(quitItem)

        return items
    }

    // MARK: Bookmarks section -------------------------------------------------

    func buildBookmarksSection(bookmarks: [Bookmark]) -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        let bookmarksItem = NSMenuItem(
            title: "status_bar_section_bookmarks_title".loco(),
            action: nil,
            keyEquivalent: ""
        )
        items.append(bookmarksItem)

        var bookmarksItems: [NSMenuItem] = []
        for bookmark in bookmarks {
            let bookmarkItem = NSMenuItem(
                title: bookmark.name,
                action: #selector(StatusBarItemController.joinBookmark),
                keyEquivalent: ""
            )
            bookmarkItem.target = target
            bookmarkItem.representedObject = bookmark
            bookmarksItems.append(bookmarkItem)
        }

        if bookmarks.count > 3 {
            let bookmarksMenu = NSMenu(title: "status_bar_section_bookmarks_menu".loco())
            bookmarksItem.submenu = bookmarksMenu
            bookmarksMenu.items = bookmarksItems

        } else {
            bookmarksItem.attributedTitle = NSAttributedString(
                string: "status_bar_section_bookmarks_title".loco(),
                attributes: [
                    NSAttributedString.Key.font: NSFont.boldSystemFont(
                        ofSize: MenuStyleConstants.defaultFontSize)
                ]
            )
            bookmarksItem.isEnabled = false
            items.append(contentsOf: bookmarksItems)
        }

        return items
    }

    // MARK: Snapshot helper ---------------------------------------------------

    /// Titles of all items – handy for plain-text snapshot tests.
    static func plainTitles(of items: [NSMenuItem]) -> [String] {
        // Hidden items (rows that aren't opened) aren't part of what users see.
        items.filter { !$0.isHidden }.map { $0.title }
    }

    // MARK: - Private helpers --------------------------------------------------

    private func makeEventItem(_ event: MBEvent) -> NSMenuItem? {
        guard shouldRenderEvent(event) else { return nil }

        let menuTitle = eventMenuTitle(for: event)
        let time = eventTimePresentation(for: event)
        let itemTitle = eventItemAttributedTitle(
            eventTitle: menuTitle,
            time: time,
            isAllDay: event.isAllDay
        )
        let eventItem = makeBaseEventItem(event: event, title: itemTitle.plain)

        applyEventItemAppearance(eventItem, event: event, title: itemTitle)
        eventItem.representedObject = event
        configureEventDetails(
            for: eventItem,
            event: event,
            menuTitle: menuTitle,
            time: time
        )

        return eventItem
    }

    private struct EventTimePresentation {
        let formatter: DateFormatter
        let start: String
        let end: String
    }

    /// Attributed menu row title: a fixed-width "start–end" time column
    /// followed by the event title. Keeping the title range around lets the
    /// appearance helpers style the title without touching the time column.
    private struct EventItemTitle {
        let attributed: NSMutableAttributedString
        let titleRange: NSRange
        var plain: String { attributed.string }
        var fullRange: NSRange { NSRange(location: 0, length: attributed.length) }
    }

    private struct EventItemStyle {
        var attributes: [NSAttributedString.Key: Any] = [:]
        var shouldShowAsActive = true
    }

    private func shouldRenderEvent(_ event: MBEvent) -> Bool {
        if event.participationStatus == .declined || event.status == .canceled,
            state.events.declinedEventsAppearance == .hide {
            return false
        }
        if event.endDate < now, state.events.pastEventsAppearance == .hide {
            return false
        }
        if event.attendees.isEmpty, state.events.personalEventsAppearance == .hide {
            return false
        }
        return true
    }

    private func eventMenuTitle(for event: MBEvent) -> String {
        var title = event.title
        if state.menu.shortenEventTitle {
            title = StatusBarTitlePolicy.shortenTitle(
                event.title,
                limit: state.menu.menuEventTitleLength,
                noTitle: "status_bar_no_title".loco()
            )
        }
        if isDismissed(event) {
            title = "[\("status_bar_event_dismissed_mark".loco())] \(title)"
        }
        return title
    }

    private func eventTimePresentation(for event: MBEvent) -> EventTimePresentation {
        let formatter = DateFormatter()
        formatter.locale = I18N.instance.locale

        switch state.timeFormat {
        case .am_pm:
            formatter.dateFormat = "h:mm a"
        case .military:
            formatter.dateFormat = "HH:mm"
        }

        guard event.isAllDay else {
            return EventTimePresentation(
                formatter: formatter,
                start: formatter.string(from: event.startDate),
                end: formatter.string(from: event.endDate)
            )
        }

        return EventTimePresentation(
            formatter: formatter,
            start: "status_bar_event_start_time_all_day".loco(),
            end: ""
        )
    }

    private func eventItemAttributedTitle(
        eventTitle: String,
        time: EventTimePresentation,
        isAllDay: Bool
    ) -> EventItemTitle {
        let timeColumn: String
        if isAllDay {
            timeColumn = time.start
        } else if state.statusBar.showEventEndTime {
            timeColumn = "\(time.start)–\(time.end)"
        } else {
            timeColumn = time.start
        }

        let timeFont = NSFont.monospacedDigitSystemFont(
            ofSize: MenuStyleConstants.defaultFontSize,
            weight: .regular
        )
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.tabStops = [
            NSTextTab(textAlignment: .left, location: timeColumnTabStopLocation(font: timeFont))
        ]
        paragraphStyle.lineBreakMode = .byTruncatingTail

        let attributed = NSMutableAttributedString(
            string: "\(timeColumn)\t\(eventTitle)",
            attributes: [.paragraphStyle: paragraphStyle]
        )
        let timeRange = NSRange(location: 0, length: (timeColumn as NSString).length)
        attributed.addAttribute(.font, value: timeFont, range: timeRange)
        if !isAllDay, state.statusBar.showEventEndTime {
            // De-emphasize the dash and end time so the start time leads the row.
            let startLength = (time.start as NSString).length
            attributed.addAttribute(
                .foregroundColor,
                value: NSColor.secondaryLabelColor,
                range: NSRange(location: startLength, length: timeRange.length - startLength)
            )
        }

        let titleStart = timeRange.length + 1
        return EventItemTitle(
            attributed: attributed,
            titleRange: NSRange(location: titleStart, length: attributed.length - titleStart)
        )
    }

    /// One shared tab stop for all rows so event titles align regardless of
    /// the rendered time strings (including the localized "All day" label).
    private func timeColumnTabStopLocation(font: NSFont) -> CGFloat {
        let timeTemplate: String
        switch state.timeFormat {
        case .am_pm:
            timeTemplate = "12:58 PM"
        case .military:
            timeTemplate = "88:88"
        }
        let templates = [
            "status_bar_event_start_time_all_day".loco(),
            state.statusBar.showEventEndTime ? "\(timeTemplate)–\(timeTemplate)" : timeTemplate
        ]
        let width = templates
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        return ceil(width) + 12
    }

    private func makeBaseEventItem(event: MBEvent, title: String) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: #selector(StatusBarItemController.clickOnEvent(sender:)),
            keyEquivalent: ""
        )
        item.target = target
        item.image = eventRowIcon(for: event)
        return item
    }

    /// Icon column for an event row, combining two preferences: the meeting
    /// service icon (where the meeting opens) and the calendar color (which
    /// calendar the event belongs to, shown as a dot or a badge).
    private func eventRowIcon(for event: MBEvent) -> NSImage? {
        let showServiceIcon = state.menu.showMeetingServiceIcon
        let showCalendarColor = state.menu.showEventCalendarColor
        let color = event.calendar.color

        guard showServiceIcon else {
            return showCalendarColor ? Self.calendarColorDot(for: color) : nil
        }
        guard event.meetingLink != nil else {
            // No meeting link: keep the icon column aligned and surface the
            // calendar color instead of an empty placeholder.
            return showCalendarColor
                ? Self.calendarColorDot(for: color)
                : getIconForMeetingService(nil)
        }
        let service = event.meetingLink?.service
        return showCalendarColor
            ? Self.badgedServiceIcon(for: service, color: color)
            : getIconForMeetingService(service)
    }

    private static var calendarDotCache: [NSColor: NSImage] = [:]

    private static func calendarColorDot(for color: NSColor) -> NSImage {
        if let cached = calendarDotCache[color] {
            return cached
        }
        let image = NSImage(size: MenuStyleConstants.iconSize, flipped: false) { _ in
            let diameter: CGFloat = 8
            let dotRect = NSRect(
                x: (MenuStyleConstants.iconSize.width - diameter) / 2,
                y: (MenuStyleConstants.iconSize.height - diameter) / 2,
                width: diameter,
                height: diameter
            )
            color.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
            return true
        }
        calendarDotCache[color] = image
        return image
    }

    private struct BadgedIconKey: Hashable {
        let service: MeetingServices?
        let color: NSColor
    }

    private static var badgedIconCache: [BadgedIconKey: NSImage] = [:]

    /// Service icon with a small calendar-color dot in the bottom-right
    /// corner, separated by a punched-out gap so it reads on any icon.
    private static func badgedServiceIcon(
        for service: MeetingServices?,
        color: NSColor
    ) -> NSImage {
        let base = getIconForMeetingService(service)
        // Template icons are tinted by AppKit at draw time; rasterizing a
        // badge onto them would break dark-mode rendering.
        guard !base.isTemplate else { return base }

        let key = BadgedIconKey(service: service, color: color)
        if let cached = badgedIconCache[key] {
            return cached
        }

        let image = NSImage(size: MenuStyleConstants.iconSize, flipped: false) { rect in
            let baseSize = base.size
            if baseSize.width > 0, baseSize.height > 0 {
                let scale = min(rect.width / baseSize.width, rect.height / baseSize.height)
                let drawSize = NSSize(
                    width: baseSize.width * scale,
                    height: baseSize.height * scale
                )
                base.draw(in: NSRect(
                    x: rect.minX + (rect.width - drawSize.width) / 2,
                    y: rect.minY + (rect.height - drawSize.height) / 2,
                    width: drawSize.width,
                    height: drawSize.height
                ))
            }

            let diameter: CGFloat = 7
            let badgeRect = NSRect(
                x: rect.maxX - diameter,
                y: rect.minY,
                width: diameter,
                height: diameter
            )
            if let context = NSGraphicsContext.current?.cgContext {
                context.saveGState()
                context.setBlendMode(.clear)
                context.fillEllipse(in: badgeRect.insetBy(dx: -1.5, dy: -1.5))
                context.restoreGState()
            }
            color.setFill()
            NSBezierPath(ovalIn: badgeRect).fill()
            return true
        }
        badgedIconCache[key] = image
        return image
    }

    private func applyEventItemAppearance(
        _ item: NSMenuItem,
        event: MBEvent,
        title: EventItemTitle
    ) {
        var style = baseEventItemStyle(for: event)

        if event.endDate < now, event.status != .canceled {
            applyPastEventAppearance(item, title: title, style: &style)
        } else if event.startDate < now, event.endDate > now, event.status != .canceled {
            applyRunningEventAppearance(item, title: title, style: style)
        } else {
            applyUpcomingEventAppearance(item, title: title, style: style)
        }
    }

    private func baseEventItemStyle(for event: MBEvent) -> EventItemStyle {
        var style = EventItemStyle()

        if event.participationStatus == .declined || event.status == .canceled {
            if state.events.declinedEventsAppearance == .show_inactive {
                style.attributes[.foregroundColor] = NSColor.disabledControlTextColor
            } else {
                style.attributes[.strikethroughStyle] = NSUnderlineStyle.thick.rawValue
            }
            style.shouldShowAsActive = false
        }

        if !event.isAllDay,
            state.events.nonAllDayEvents == .show_inactive_without_meeting_link,
            event.meetingLink == nil {
            style.attributes[.foregroundColor] = NSColor.disabledControlTextColor
        }

        applyParticipationStyle(
            statusMatches: event.participationStatus == .pending,
            showInactive: state.events.showPendingEvents == .show_inactive,
            showUnderlined: state.events.showPendingEvents == .show_underlined,
            to: &style.attributes
        )
        applyParticipationStyle(
            statusMatches: event.participationStatus == .tentative,
            showInactive: state.events.showTentativeEvents == .show_inactive,
            showUnderlined: state.events.showTentativeEvents == .show_underlined,
            to: &style.attributes
        )

        if event.attendees.isEmpty, state.events.personalEventsAppearance == .show_inactive {
            style.attributes[.foregroundColor] = NSColor.disabledControlTextColor
            style.shouldShowAsActive = false
        }

        return style
    }

    private func applyParticipationStyle(
        statusMatches: Bool,
        showInactive: Bool,
        showUnderlined: Bool,
        to attributes: inout [NSAttributedString.Key: Any]
    ) {
        guard statusMatches else { return }

        if showInactive {
            attributes[.foregroundColor] = NSColor.disabledControlTextColor
        } else if showUnderlined {
            attributes[.underlineStyle] =
                NSUnderlineStyle.single.rawValue
                | NSUnderlineStyle.patternDot.rawValue
                | NSUnderlineStyle.byWord.rawValue
        }
    }

    private func applyPastEventAppearance(
        _ item: NSMenuItem,
        title: EventItemTitle,
        style: inout EventItemStyle
    ) {
        item.state = .on
        item.onStateImage = nil

        let attributed = title.attributed
        attributed.addAttributes(style.attributes, range: title.fullRange)
        if state.events.pastEventsAppearance == .show_inactive {
            attributed.addAttribute(
                .foregroundColor,
                value: NSColor.disabledControlTextColor,
                range: title.fullRange
            )
            item.image = item.image?.tintedDisabled()
        }
        item.attributedTitle = attributed
    }

    private func applyRunningEventAppearance(
        _ item: NSMenuItem,
        title: EventItemTitle,
        style: EventItemStyle
    ) {
        item.state = .mixed
        item.mixedStateImage = nil

        let attributed = title.attributed
        attributed.addAttributes(style.attributes, range: title.fullRange)
        attributed.addAttribute(
            .font,
            value: runningEventFont(shouldShowAsActive: style.shouldShowAsActive),
            range: title.titleRange
        )
        if style.shouldShowAsActive {
            let runningImage = NSTextAttachment()
            runningImage.image = NSImage(named: MenuStyleConstants.runningIconName)
            runningImage.image?.size = MenuStyleConstants.iconSize
            attributed.append(NSAttributedString(string: " "))
            attributed.append(NSAttributedString(attachment: runningImage))
        }
        item.attributedTitle = attributed
    }

    private func runningEventFont(shouldShowAsActive: Bool) -> NSFont {
        if shouldShowAsActive, state.events.showTentativeEvents != .show_underlined {
            return NSFont.boldSystemFont(ofSize: MenuStyleConstants.defaultFontSize)
        }
        return NSFont.systemFont(ofSize: MenuStyleConstants.defaultFontSize)
    }

    private func applyUpcomingEventAppearance(
        _ item: NSMenuItem,
        title: EventItemTitle,
        style: EventItemStyle
    ) {
        item.state = .off
        item.offStateImage = nil
        let attributed = title.attributed
        attributed.addAttributes(style.attributes, range: title.fullRange)
        item.attributedTitle = attributed
    }

    private func configureEventDetails(
        for item: NSMenuItem,
        event: MBEvent,
        menuTitle: String,
        time: EventTimePresentation
    ) {
        guard state.menu.showEventDetails else {
            return
        }

        let menu = NSMenu(title: "Item \(menuTitle) menu")
        item.submenu = menu

        addEventTitle(to: menu, event: event)
        addEventStatus(to: menu, event: event)
        addEventDuration(to: menu, event: event, time: time)
        addEventCalendar(to: menu, event: event)
        addEventLocation(to: menu, event: event)
        addEventOrganizer(to: menu, event: event)
        addEventNotes(to: menu, event: event)
        addEventAttendees(to: menu, event: event)
        if let attachmentsItem = makeAttachmentsMenuItem(for: event) {
            menu.addItem(.separator())
            menu.addItem(attachmentsItem)
        }
        addEventActions(to: menu, event: event)
    }

    // MARK: Documents / attachments (#917) -----------------------------------

    /// How many documents the featured meeting shows inline before collapsing
    /// the rest into an "Attachments" submenu, keeping the dropdown compact.
    static let maxInlineFeaturedDocuments = 3

    /// Upcoming (or running) meetings in the event list show their documents
    /// indented right below their row. The featured meeting already shows
    /// them in the top section, and past meetings stay collapsed.
    private func makeExpandedDocumentItems(for event: MBEvent) -> [NSMenuItem] {
        guard event.endDate > now, event.id != state.nextEvent?.id else { return [] }
        let items = makeFeaturedDocumentItems(for: event)
        for item in items {
            item.indentationLevel = 1
        }
        return items
    }

    /// Upcoming rows open in place on click (instead of joining), like the
    /// featured meeting: a join row, the attachments, then the actions.
    /// Every upcoming meeting opens; parts it doesn't have (Join without a
    /// link, attachments, rooms) are simply left out, so a plain
    /// "Lunch break" shows just its actions.
    static func isExpandable(_ event: MBEvent, now: Date) -> Bool {
        event.startDate > now
    }

    /// Turns `item` into a row that opens in place, and returns its detail
    /// items (hidden unless the user opened it earlier).
    private func makeExpandableRow(_ item: NSMenuItem, event: MBEvent) -> [NSMenuItem] {
        let rooms = makeRoomChipsItem(for: event, leading: 28)
        let documents = makeFeaturedDocumentItems(for: event)
        // Nothing to open in place (no link, documents, rooms or RSVP):
        // the row just offers its actions as a regular submenu.
        if event.meetingLink == nil, rooms == nil, documents.isEmpty, !Self.canRespond(to: event, now: now) {
            let submenu = NSMenu(title: "status_bar_control_actions".loco())
            addEventActions(to: submenu, event: event, includeResponses: false)
            item.submenu = submenu
            // No link to join: clicking the title must not start a new call.
            item.action = nil
            return []
        }
        var children: [NSMenuItem] = []
        if let details = makeEventDetailsLineItem(for: event) { children.append(details) }
        if let rooms { children.append(rooms) }
        children.append(contentsOf: documents)
        children.append(makeActionBarItem(for: event, showsJoin: event.meetingLink != nil))
        let expanded = expandedEventIDs.contains(event.id)
        for child in children {
            child.indentationLevel = 1
            child.isHidden = !expanded
        }
        let controller = target as? StatusBarItemController
        item.view = ExpandableEventRowView(
            title: item.attributedTitle ?? NSAttributedString(string: item.title),
            children: children
        ) { [weak controller] isExpanded in
            controller?.setEvent(event.id, expanded: isExpanded)
        }
        return children
    }

    /// Join, Yes / Maybe / No in one click; everything else is in the item's
    /// submenu (opened by hovering the row, marked ⋯).
    private func makeActionBarItem(for event: MBEvent, showsJoin: Bool, leading: CGFloat = 28) -> NSMenuItem {
        // Titled for accessibility and tests; the view draws the row.
        let item = NSMenuItem(title: "status_bar_control_actions".loco(), action: nil, keyEquivalent: "")
        item.representedObject = event
        let submenu = NSMenu(title: "status_bar_control_actions".loco())
        addEventActions(to: submenu, event: event, includeResponses: false)
        item.submenu = submenu

        let controller = target as? StatusBarItemController
        let current: EventResponse? = switch event.participationStatus {
        case .accepted: .accept
        case .tentative: .maybe
        case .declined: .decline
        default: nil
        }
        let bar = MeetingActionBarView(
            showsJoin: showsJoin,
            showsResponses: Self.canRespond(to: event, now: now),
            leading: leading,
            onJoin: { [weak item, weak controller] in
                guard let item, let controller else { return }
                item.menu?.cancelTracking()
                controller.joinEvent(sender: item)
            },
            onRespond: { [weak item, weak controller] response in
                controller?.respond(to: EventResponseRequest(
                    response: response,
                    eventID: event.id,
                    calendarID: event.calendar.id,
                    fallbackURL: event.calendarOpenURL
                ), closingMenu: item?.menu)
            },
            response: current
        )
        let hosting = NSHostingView(rootView: bar)
        hosting.frame = NSRect(x: 0, y: 0, width: MeetingSummaryView.preferredWidth, height: MeetingActionBarView.height)
        hosting.autoresizingMask = [.width]
        item.view = hosting
        return item
    }

    static func canRespond(to event: MBEvent, now: Date) -> Bool {
        !event.attendees.isEmpty && event.endDate > now
    }

    /// "25 min · with Åsa Lind" or "38 people · 21 going".
    private func makeEventDetailsLineItem(for event: MBEvent) -> NSMenuItem? {
        var parts: [String] = []
        if let service = event.meetingLink?.service.flatMap(MeetingProvider.provider(for:))?.displayName {
            parts.append(service)
        }
        if !event.isAllDay {
            let minutes = Int(event.endDate.timeIntervalSince(event.startDate) / 60)
            parts.append("status_bar_details_minutes".loco(String(minutes)))
        }
        let others = event.attendees.filter { !$0.isCurrentUser }
        if others.count == 1, let other = others.first {
            parts.append("status_bar_details_with".loco(other.name))
        } else if others.count > 1 {
            let going = event.attendees.filter { $0.status == .accepted }.count
            parts.append("status_bar_details_people".loco(String(event.attendees.count), String(going)))
        }
        guard !parts.isEmpty else { return nil }
        let item = NSMenuItem(title: parts.joined(separator: " · "), action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: item.title, attributes: [
            .font: NSFont.systemFont(ofSize: MenuStyleConstants.defaultFontSize - 2),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
        item.isEnabled = false
        return item
    }

    /// Booked rooms as light grey chips, so you know where to go in the office.
    private func makeRoomChipsItem(
        for event: MBEvent, leading: CGFloat, prominent: Bool = false
    ) -> NSMenuItem? {
        let places: [String]
        let isLocation: Bool
        if placeChipMode == .off {
            places = event.rooms
            isLocation = false
        } else {
            let workingLocation = workingLocationsByDay[MeetingPlacePolicy.dayKey(event.startDate)]
            guard MeetingPlacePolicy.shouldShow(mode: placeChipMode, workingLocation: workingLocation) else {
                return nil
            }
            places = MeetingPlacePolicy.places(rooms: event.rooms, location: event.location)
            isLocation = event.rooms.isEmpty
        }
        guard !places.isEmpty else { return nil }
        let item = NSMenuItem()
        item.isEnabled = false
        let hosting = NSHostingView(rootView: RoomChipsView(
            rooms: places, leading: leading,
            prominent: prominent && placeChipMode != .off, isLocation: isLocation))
        hosting.frame = NSRect(x: 0, y: 0, width: MeetingSummaryView.preferredWidth, height: RoomChipsView.height + (prominent ? 4 : 0))
        hosting.autoresizingMask = [.width]
        item.view = hosting
        return item
    }

    private func makeFeaturedDocumentItems(for event: MBEvent) -> [NSMenuItem] {
        let documents = event.documents
        guard !documents.isEmpty else { return [] }
        if documents.count > Self.maxInlineFeaturedDocuments,
           let attachmentsItem = makeAttachmentsMenuItem(for: event) {
            return [attachmentsItem]
        }
        return documents.map(makeDocumentItem)
    }

    private func makeAttachmentsMenuItem(for event: MBEvent) -> NSMenuItem? {
        guard !event.documents.isEmpty else { return nil }
        let title = "status_bar_submenu_attachments".loco()
        let item = NSMenuItem(title: "\(title) (\(event.documents.count))", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: title)
        let menu = NSMenu(title: title)
        for document in event.documents {
            menu.addItem(makeDocumentItem(document))
        }
        item.submenu = menu
        return item
    }

    private func makeDocumentItem(_ document: EventDocument) -> NSMenuItem {
        let item = NSMenuItem(
            title: document.title,
            action: #selector(StatusBarItemController.openEventDocument),
            keyEquivalent: ""
        )
        item.target = target
        item.representedObject = document.url
        item.toolTip = document.url.absoluteString
        DocumentIconProvider.shared.applyIcon(for: document, to: item)
        return item
    }

    private func addEventTitle(to menu: NSMenu, event: MBEvent) {
        let titleItem = menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
        titleItem.view = createNSViewFromText(
            text: event.title,
            font: NSFont.boldSystemFont(ofSize: 15),
            maxWidth: 420
        )
        menu.addItem(NSMenuItem.separator())
    }

    private func addEventStatus(to menu: NSMenu, event: MBEvent) {
        let status: String
        switch event.participationStatus {
        case .accepted:
            status = "status_bar_submenu_status_accepted".loco()
        case .declined:
            status = "status_bar_submenu_status_declined".loco()
        case .tentative:
            status = "status_bar_submenu_status_tentative".loco()
        case .pending:
            status = "status_bar_submenu_status_pending".loco()
        case .unknown:
            status = "status_bar_submenu_status_unknown".loco()
        default:
            status = "status_bar_submenu_status_default_extended".loco(
                String(describing: event.status)
            )
        }
        menu.addItem(
            withTitle: "status_bar_submenu_status_title".loco(status),
            action: nil,
            keyEquivalent: ""
        )
        menu.addItem(NSMenuItem.separator())
    }

    private func addEventDuration(
        to menu: NSMenu,
        event: MBEvent,
        time: EventTimePresentation
    ) {
        guard !event.isAllDay else { return }

        let durationMinutes = String(Int(event.endDate.timeIntervalSince(event.startDate) / 60))
        let title = "status_bar_submenu_duration_all_day".loco(
            time.start,
            time.formatter.string(from: event.endDate),
            durationMinutes
        )
        menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
    }

    private func addEventCalendar(to menu: NSMenu, event: MBEvent) {
        guard state.hasMultipleSelectedCalendars else { return }

        menu.addItem(
            withTitle: "status_bar_submenu_calendar_title".loco(event.calendar.title),
            action: nil,
            keyEquivalent: ""
        )
        menu.addItem(NSMenuItem.separator())
    }

    private func addEventLocation(to menu: NSMenu, event: MBEvent) {
        guard let location = event.location, !location.isEmpty else { return }

        menu.addItem(
            withTitle: "status_bar_submenu_location_title".loco(),
            action: nil,
            keyEquivalent: ""
        )
        let locationItem = menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
        locationItem.view = createNSViewFromText(text: location, maxWidth: 420)
        menu.addItem(NSMenuItem.separator())
    }

    private func addEventOrganizer(to menu: NSMenu, event: MBEvent) {
        guard let organizer = event.organizer else { return }

        menu.addItem(
            withTitle: "status_bar_submenu_organizer_title".loco(organizer.name),
            action: nil,
            keyEquivalent: ""
        )
        menu.addItem(NSMenuItem.separator())
    }

    private func addEventNotes(to menu: NSMenu, event: MBEvent) {
        guard let rawNotes = event.notes else { return }
        let notes = cleanUpNotes(rawNotes)
        guard !notes.isEmpty else { return }

        menu.addItem(
            withTitle: "status_bar_submenu_notes_title".loco(),
            action: nil,
            keyEquivalent: ""
        )
        let notesItem = menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
        notesItem.view = createNSViewFromText(text: notes, maxWidth: 420)
        menu.addItem(NSMenuItem.separator())
    }

    private func addEventAttendees(to menu: NSMenu, event: MBEvent) {
        guard !event.attendees.isEmpty else { return }

        let attendees = event.attendees.sorted { $0.status.rawValue < $1.status.rawValue }
        menu.addItem(
            withTitle: "status_bar_submenu_attendees_title".loco(attendees.count),
            action: nil,
            keyEquivalent: ""
        )
        for attendee in attendees {
            menu.addItem(makeAttendeeItem(attendee))
        }
        menu.addItem(NSMenuItem.separator())
    }

    private func makeAttendeeItem(_ attendee: MBEventAttendee) -> NSMenuItem {
        var attributes: [NSAttributedString.Key: Any] = [:]
        let name = attendee.isCurrentUser
            ? "status_bar_submenu_attendees_you".loco(attendee.name)
            : attendee.name
        let roleMark = attendee.optional ? "*" : ""

        let status: String
        switch attendee.status {
        case .declined:
            status = ""
            attributes[.strikethroughStyle] = NSUnderlineStyle.thick.rawValue
        case .tentative:
            status = "status_bar_submenu_attendees_status_tentative".loco()
        case .pending:
            status = "status_bar_submenu_attendees_status_unknown".loco()
        default:
            status = ""
        }

        let title = "- \(name)\(roleMark) \(status)"
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: title, attributes: attributes)
        return item
    }

    private func addEventActions(to menu: NSMenu, event: MBEvent, includeResponses: Bool = true) {
        if let alternateLinksItem = makeAlternateMeetingLinksMenu(for: event) {
            menu.addItem(alternateLinksItem)
        }

        if event.meetingLink != nil {
            addEventAction(
                to: menu,
                title: "status_bar_submenu_copy_meeting_link".loco(),
                action: #selector(StatusBarItemController.copyEventMeetingLink),
                representedObject: event
            )
        }

        if isDismissed(event) {
            addEventAction(
                to: menu,
                title: "status_bar_submenu_undismiss_meeting".loco(),
                action: #selector(StatusBarItemController.undismissEvent),
                representedObject: event
            )
        } else {
            addEventAction(
                to: menu,
                title: "status_bar_submenu_dismiss_meeting".loco(),
                action: #selector(StatusBarItemController.dismissEvent),
                representedObject: event
            )
        }

        addEventAction(
            to: menu,
            title: "status_bar_submenu_email_attendees".loco(),
            action: #selector(StatusBarItemController.emailAttendees),
            representedObject: event
        )
        // Only offer "Open in Calendar" when the source provides a usable URL
        // (EventKit: ical://ekevent/…, Google: htmlLink). Hidden otherwise so we
        // never open a broken ical:// link for a Google event id.
        if let calendarOpenURL = event.calendarOpenURL {
            addEventAction(
                to: menu,
                title: "status_bar_submenu_open_in_calendar".loco(),
                action: #selector(StatusBarItemController.openEventInCalendar),
                representedObject: calendarOpenURL
            )
        }

        if isFantasticalInstalled {
            addEventAction(
                to: menu,
                title: "status_bar_submenu_open_in_fantastical".loco(),
                action: #selector(StatusBarItemController.openEventInFantastical),
                representedObject: event
            )
        }

        if includeResponses {
            addEventResponseActions(to: menu, event: event)
        }
    }

    /// Accept / Maybe / Decline, separate from Dismiss (which only hides the
    /// meeting in MeetingBar). The current answer is check-marked.
    private func addEventResponseActions(to menu: NSMenu, event: MBEvent) {
        guard !event.attendees.isEmpty, event.endDate > now else { return }
        let responses: [(EventResponse, String, MBEventAttendeeStatus)] = [
            (.accept, "status_bar_submenu_rsvp_accept", .accepted),
            (.maybe, "status_bar_submenu_rsvp_maybe", .tentative),
            (.decline, "status_bar_submenu_rsvp_decline", .declined)
        ]
        var items: [NSMenuItem] = []
        for (response, key, status) in responses {
            let item = NSMenuItem(
                title: key.loco(),
                action: #selector(StatusBarItemController.respondToEvent(sender:)),
                keyEquivalent: ""
            )
            item.target = target
            item.representedObject = EventResponseRequest(
                response: response,
                eventID: event.id,
                calendarID: event.calendar.id,
                fallbackURL: event.calendarOpenURL
            )
            item.state = event.participationStatus == status ? .on : .off
            items.append(item)
        }
        menu.addItem(.separator())
        menu.addItem(statusItem(title: "status_bar_submenu_rsvp_title".loco()))
        items.forEach(menu.addItem)
    }

    private func addEventAction(
        to menu: NSMenu,
        title: String,
        action: Selector,
        representedObject: Any
    ) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = target
        item.representedObject = representedObject
    }

    private func isDismissed(_ event: MBEvent) -> Bool {
        state.events.dismissedEvents.contains { $0.id == event.id }
    }

    private func makeAlternateMeetingLinksMenu(for event: MBEvent) -> NSMenuItem? {
        guard !event.alternateMeetingLinkCandidates.isEmpty else { return nil }

        let title = "status_bar_join_with_other_link".loco()
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        for candidate in event.alternateMeetingLinkCandidates {
            let alternateItem = menu.addItem(
                withTitle: alternateMeetingLinkTitle(for: candidate),
                action: #selector(StatusBarItemController.joinMeetingLinkCandidate),
                keyEquivalent: ""
            )
            alternateItem.target = target
            alternateItem.representedObject = candidate
            alternateItem.toolTip = candidate.url.absoluteString
        }
        item.submenu = menu
        return item
    }

    private func alternateMeetingLinkTitle(for candidate: MeetingLinkCandidate) -> String {
        let service = candidate.service?.localizedValue ?? "constants_meeting_service_other".loco()
        guard let host = candidate.url.host else { return service }
        return "\(service) - \(host)"
    }
}
