import Foundation

/// Last known snapshot per provider, so indicators show something honest at launch
/// (marked "cached" until a source confirms it). Contains percentages and reset times only.
public struct SnapshotCache: Sendable {
    public let url: URL

    public init(url: URL = SnapshotCache.defaultURL()) {
        self.url = url
    }

    public static func defaultURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AIquota/snapshots.json")
    }

    public func load() -> [ProviderID: QuotaSnapshot] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: QuotaSnapshot].self, from: data) else { return [:] }
        var result: [ProviderID: QuotaSnapshot] = [:]
        for (key, snapshot) in decoded where !snapshot.isFixture {
            result[ProviderID(key)] = snapshot
        }
        return result
    }

    public func save(_ snapshots: [ProviderID: QuotaSnapshot]) {
        var encodable: [String: QuotaSnapshot] = [:]
        for (id, snapshot) in snapshots where !snapshot.isFixture {
            encodable[id.rawValue] = snapshot
        }
        guard let data = try? JSONEncoder().encode(encodable) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
