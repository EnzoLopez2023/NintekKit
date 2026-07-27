import Foundation

/// A shared item captured by the Share Extension (Phase 7.5) — "Add to
/// Workshop" from Safari/Photos/Pinterest. The extension has no
/// authenticated `WorkshopAPI` of its own (same constraint as the Phase 7.2
/// widget button), so it only queues the raw content here; the app performs
/// the real project-create/image-upload the next time it's opened.
public struct PendingShareItem: Codable, Sendable, Identifiable, Equatable {
    public enum Kind: String, Codable, Sendable { case url, image }

    public let id: UUID
    public let kind: Kind
    /// Set when `kind == .url` — the shared page's URL.
    public let urlString: String?
    /// Set when `kind == .image` — the filename inside the App Group's
    /// `PendingShares` directory (image bytes are too large for UserDefaults).
    public let imageFilename: String?
    public let receivedAt: Date

    fileprivate init(kind: Kind, urlString: String? = nil, imageFilename: String? = nil) {
        self.id = UUID(); self.kind = kind
        self.urlString = urlString; self.imageFilename = imageFilename
        self.receivedAt = Date()
    }
}

/// Queue of shared items awaiting the app's attention, handed off across the
/// process boundary via the same App Group the widgets use.
public enum ShareQueue {
    public static let appGroup = "group.com.nintek.workshop"
    private static let key = "workshop.share.pending"

    private static var imagesDirectory: URL? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return nil }
        let dir = container.appendingPathComponent("PendingShares", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static func enqueueURL(_ urlString: String) {
        var items = loadAll()
        items.append(PendingShareItem(kind: .url, urlString: urlString))
        save(items)
    }

    /// Writes the image to the shared container and queues a reference to it.
    @discardableResult
    public static func enqueueImage(_ data: Data) -> Bool {
        guard let dir = imagesDirectory else { return false }
        let filename = "\(UUID().uuidString).jpg"
        guard (try? data.write(to: dir.appendingPathComponent(filename))) != nil else { return false }
        var items = loadAll()
        items.append(PendingShareItem(kind: .image, imageFilename: filename))
        save(items)
        return true
    }

    /// Reads the image bytes for a queued `.image` item.
    public static func imageData(for item: PendingShareItem) -> Data? {
        guard item.kind == .image, let filename = item.imageFilename, let dir = imagesDirectory else { return nil }
        return try? Data(contentsOf: dir.appendingPathComponent(filename))
    }

    public static func loadAll() -> [PendingShareItem] {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key),
              let items = try? JSONDecoder().decode([PendingShareItem].self, from: data) else { return [] }
        return items
    }

    /// Removes a queued item once the app has handled it (or the user
    /// dismisses it), cleaning up its image file if any.
    public static func remove(_ item: PendingShareItem) {
        if let filename = item.imageFilename, let dir = imagesDirectory {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(filename))
        }
        var items = loadAll()
        items.removeAll { $0.id == item.id }
        save(items)
    }

    private static func save(_ items: [PendingShareItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults(suiteName: appGroup)?.set(data, forKey: key)
    }
}
