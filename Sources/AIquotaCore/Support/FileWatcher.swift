import CoreServices
import Foundation

/// Thin FSEvents wrapper. Watches directories recursively and reports changed paths that pass
/// `filter`. FSEvents coalesces bursts using `latency`, so the callback stays cheap even in
/// directories with heavy churn.
public final class FileWatcher: @unchecked Sendable {
    public typealias Handler = @Sendable ([String]) -> Void

    private let paths: [String]
    private let latency: CFTimeInterval
    private let filter: @Sendable (String) -> Bool
    private let handler: Handler
    private let queue = DispatchQueue(label: "aiquota.filewatcher", qos: .utility)
    private var stream: FSEventStreamRef?

    public init(paths: [String], latency: CFTimeInterval = 1.0,
                filter: @escaping @Sendable (String) -> Bool = { _ in true },
                handler: @escaping Handler) {
        self.paths = paths
        self.latency = latency
        self.filter = filter
        self.handler = handler
    }

    deinit { stop() }

    /// Returns false when none of the paths exist yet.
    @discardableResult
    public func start() -> Bool {
        guard stream == nil else { return true }
        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
        guard !existing.isEmpty else { return false }

        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            let array = unsafeBitCast(eventPaths, to: NSArray.self)
            var changed: [String] = []
            changed.reserveCapacity(count)
            for case let path as String in array where watcher.filter(path) {
                changed.append(path)
            }
            if !changed.isEmpty { watcher.handler(changed) }
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
                           | kFSEventStreamCreateFlagNoDefer)
        guard let created = FSEventStreamCreate(kCFAllocatorDefault, callback, &context, existing as CFArray,
                                                FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency,
                                                flags) else { return false }
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
        stream = created
        return true
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
