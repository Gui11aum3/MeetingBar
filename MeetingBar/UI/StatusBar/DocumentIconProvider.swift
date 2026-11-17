//
//  DocumentIconProvider.swift
//  MeetingBar
//
//  Menu icons for invite documents (#917). Shows the site's own favicon when
//  it has been fetched, otherwise an SF Symbol for the document type. Only
//  the public `/favicon.ico` of the link's host is requested, through an
//  ephemeral cookie-less session; document contents are never fetched.
//

import AppKit

@MainActor
final class DocumentIconProvider {
    static let shared = DocumentIconProvider()

    private static let iconSize = NSSize(width: 16, height: 16)
    private var favicons: [String: NSImage] = [:]
    private var inFlight: Set<String> = []
    private var failed: Set<String> = []
    /// Menu items waiting for a favicon, refreshed in place when it arrives.
    private var waitingItems: [String: NSHashTable<NSMenuItem>] = [:]

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 5
        return URLSession(configuration: configuration)
    }()

    func applyIcon(for document: EventDocument, to item: NSMenuItem) {
        Self.setIcon(Self.symbol(for: document.kind), on: item)
        guard let iconURL = Self.iconURL(for: document) else { return }
        let key = iconURL.absoluteString
        if let favicon = favicons[key] {
            Self.setIcon(favicon, on: item)
            return
        }
        guard !failed.contains(key) else { return }
        waitingItems[key, default: .weakObjects()].add(item)
        fetchIcon(key: key, url: iconURL)
    }

    /// Provider icon (Drive `iconLink`, requested at 32 px for Retina) when
    /// known, otherwise the site's `/favicon.ico`.
    private static func iconURL(for document: EventDocument) -> URL? {
        if let iconURL = document.iconURL {
            let hiDPI = iconURL.absoluteString.replacingOccurrences(of: "/16/type/", with: "/32/type/")
            return URL(string: hiDPI) ?? iconURL
        }
        // Google files all live on drive.google.com or docs.google.com, whose
        // favicon is the Drive logo; use the per-type icon Drive publishes.
        if let mimeType = googleMimeType(for: document.kind) {
            return URL(string: "https://drive-thirdparty.googleusercontent.com/32/type/\(mimeType)")
        }
        guard let host = document.url.host?.lowercased() else { return nil }
        return URL(string: "https://\(host)/favicon.ico")
    }

    private static func googleMimeType(for kind: EventDocumentKind) -> String? {
        switch kind {
        case .googleDocs: "application/vnd.google-apps.document"
        case .googleSheets: "application/vnd.google-apps.spreadsheet"
        case .googleSlides: "application/vnd.google-apps.presentation"
        case .googleForms: "application/vnd.google-apps.form"
        default: nil
        }
    }

    private func fetchIcon(key: String, url: URL) {
        guard !inFlight.contains(key) else { return }
        inFlight.insert(key)
        session.dataTask(with: url) { [weak self] data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let image = (200..<300).contains(status) ? data.flatMap(NSImage.init(data:)) : nil
            Task { @MainActor in
                self?.finishFetch(host: key, image: image)
            }
        }.resume()
    }

    private func finishFetch(host: String, image: NSImage?) {
        inFlight.remove(host)
        guard let image, image.isValid else {
            failed.insert(host)
            waitingItems[host] = nil
            return
        }
        image.size = Self.iconSize
        favicons[host] = image
        for item in waitingItems[host]?.allObjects ?? [] {
            Self.setIcon(image, on: item)
        }
        waitingItems[host] = nil
    }

    /// Draws the icon inline at the start of the title. `NSMenuItem.image`
    /// is not rendered in MeetingBar's status menu on current macOS (event
    /// rows' service icons are missing too), so this uses a text attachment,
    /// like the running-meeting indicator.
    private static func setIcon(_ image: NSImage?, on item: NSMenuItem) {
        let font = NSFont.menuFont(ofSize: 0)
        let title = NSMutableAttributedString()
        if let image {
            let attachment = NSTextAttachment()
            attachment.image = image
            // Centre the icon on the text's cap height.
            attachment.bounds = NSRect(
                x: 0,
                y: (font.capHeight - iconSize.height) / 2,
                width: iconSize.width,
                height: iconSize.height
            )
            title.append(NSAttributedString(attachment: attachment))
            title.append(NSAttributedString(string: "  "))
        }
        title.append(NSAttributedString(string: item.title))
        title.addAttribute(.font, value: font, range: NSRange(location: 0, length: title.length))
        item.attributedTitle = title
    }

    private static func symbol(for kind: EventDocumentKind) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            .applying(.init(paletteColors: [.secondaryLabelColor]))
        return NSImage(systemSymbolName: kind.symbolName, accessibilityDescription: kind.rawValue)?
            .withSymbolConfiguration(configuration)
    }
}
