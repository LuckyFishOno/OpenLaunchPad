import AppCore
import CoreServices
import Foundation

/// Watches the application folders and their subfolders. A folder that does not
/// exist yet, such as ~/Applications, is noticed when it is created.
@MainActor final class ApplicationDirectoryMonitor {
    private var stream: FileEventStream?
    private var debounceTask: Task<Void, Never>?
    private let roots: [URL]
    private let onChange: @MainActor () -> Void

    init(
        roots: [URL] = StandardApplicationDiscoverySource.defaultRoots, onChange: @escaping @MainActor () -> Void
    ) {
        self.roots = roots
        self.onChange = onChange
    }

    deinit { debounceTask?.cancel() }

    func start() {
        guard stream == nil else { return }
        stream = FileEventStream(paths: roots.map { $0.resolvingSymlinksInPath().path }) { [weak self] paths in
            guard paths.contains(where: ApplicationDirectoryChange.affectsCatalog(path:)) else { return }
            self?.scheduleChange()
        }
    }

    private func scheduleChange() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.onChange()
        }
    }
}

/// Owns one FSEvents stream that reports the paths of changed directories.
private final class FileEventStream {
    private final class Handler: Sendable {
        let onEvents: @MainActor @Sendable ([String]) -> Void
        init(_ onEvents: @escaping @MainActor @Sendable ([String]) -> Void) { self.onEvents = onEvents }
    }

    private static let latency: CFTimeInterval = 0.3
    private let stream: FSEventStreamRef

    init?(paths: [String], onEvents: @escaping @MainActor @Sendable ([String]) -> Void) {
        let handler = Handler(onEvents)
        // The stream retains the handler until it is released.
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(handler).toOpaque(),
            retain: { info in
                info.map { UnsafeRawPointer(Unmanaged<Handler>.fromOpaque($0).retain().toOpaque()) }
            },
            release: { info in
                if let info { Unmanaged<Handler>.fromOpaque(info).release() }
            }, copyDescription: nil)
        let flags = kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagWatchRoot
        let callback: FSEventStreamCallback = { _, info, _, paths, _, _ in
            guard let info,
                let paths = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String]
            else { return }
            let handler = Unmanaged<Handler>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { handler.onEvents(paths) }
        }
        guard
            let stream = FSEventStreamCreate(
                nil, callback, &context, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                Self.latency, FSEventStreamCreateFlags(flags))
        else { return nil }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    deinit {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
