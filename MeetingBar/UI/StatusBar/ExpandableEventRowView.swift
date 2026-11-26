//
//  ExpandableEventRowView.swift
//  MeetingBar
//
//  Event-list row for upcoming meetings that opens in place: a click shows or
//  hides the meeting's details (join, attachments, actions) without closing
//  the menu. A standard NSMenuItem always ends menu tracking on click, so the
//  row is drawn by this view, matching the native item look.
//

import AppKit

final class ExpandableEventRowView: NSView {
    private let children: [NSMenuItem]
    private let onToggle: (Bool) -> Void

    private static let horizontalInset: CGFloat = 5
    private static let textLeading: CGFloat = 17

    init(title: NSAttributedString, children: [NSMenuItem], onToggle: @escaping (Bool) -> Void) {
        self.children = children
        self.onToggle = onToggle
        let height = max(22, ceil(title.size().height) + 6, MenuStyleConstants.defaultFontSize + 12)
        let width = Self.textLeading + ceil(title.size().width) + 24
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        autoresizingMask = [.width]
        setAccessibilityElement(true)
        setAccessibilityRole(.disclosureTriangle)
        setAccessibilityLabel(title.string)
    }

    override func accessibilityPerformPress() -> Bool {
        toggle()
        return true
    }

    override func isAccessibilityExpanded() -> Bool { isExpanded }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var isExpanded: Bool { children.contains { !$0.isHidden } }

    override func draw(_ dirtyRect: NSRect) {
        guard let item = enclosingMenuItem else { return }
        let highlighted = item.isHighlighted
        if highlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(
                roundedRect: bounds.insetBy(dx: Self.horizontalInset, dy: 0),
                xRadius: 5, yRadius: 5
            ).fill()
        }

        // No service icon: plain rows don't show one either.
        let x = Self.textLeading

        let title = NSMutableAttributedString(
            attributedString: item.attributedTitle ?? NSAttributedString(string: item.title)
        )
        let fullRange = NSRange(location: 0, length: title.length)
        // Native rows fall back to the menu font; drawing doesn't, so fill it in.
        let menuFont = NSFont.menuFont(ofSize: MenuStyleConstants.defaultFontSize)
        title.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            if value == nil { title.addAttribute(.font, value: menuFont, range: range) }
        }
        if highlighted {
            title.addAttribute(.foregroundColor, value: NSColor.selectedMenuItemTextColor, range: fullRange)
        }
        // Trailing chevron, like a submenu arrow: › closed, ⌄ open.
        let chevronName = isExpanded ? "chevron.down" : "chevron.right"
        if let chevron = NSImage(systemSymbolName: chevronName, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold)) {
            let tint = highlighted ? NSColor.selectedMenuItemTextColor : NSColor.tertiaryLabelColor
            let tinted = NSImage(size: chevron.size, flipped: false) { rect in
                chevron.draw(in: rect)
                tint.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(at: NSPoint(
                x: bounds.width - 27,
                y: (bounds.height - chevron.size.height) / 2
            ), from: .zero, operation: .sourceOver, fraction: 1)
        }
        let textRect = NSRect(x: x, y: 0, width: bounds.width - x - 34, height: bounds.height)
        let size = title.size()
        title.draw(
            with: NSRect(x: textRect.minX, y: (bounds.height - size.height) / 2, width: textRect.width, height: size.height),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        )
    }

    override func mouseUp(with event: NSEvent) {
        toggle()
    }

    private func toggle() {
        let expand = !isExpanded
        children.forEach { $0.isHidden = !expand }
        onToggle(expand)
        needsDisplay = true
    }
}
