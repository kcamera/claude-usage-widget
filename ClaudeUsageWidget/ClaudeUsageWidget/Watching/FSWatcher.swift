import Foundation
import CoreServices

/// Watches a directory tree using FSEvents. Coalesces bursts of events with a small debounce
/// so we don't re-parse on every line append.
final class FSWatcher: @unchecked Sendable {
    private let path: String
    private let debounce: TimeInterval
    private let onChange: @Sendable () -> Void

    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.kcamera.claudeusagewidget.fswatcher")
    private var debounceWorkItem: DispatchWorkItem?

    init(path: String, debounce: TimeInterval = 1.0, onChange: @escaping @Sendable () -> Void) {
        self.path = path
        self.debounce = debounce
        self.onChange = onChange
    }

    func start() {
        queue.async { [weak self] in
            guard let self, self.stream == nil else { return }
            let context = UnsafeMutablePointer<FSEventStreamContext>.allocate(capacity: 1)
            context.initialize(to: FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil,
                release: nil,
                copyDescription: nil
            ))
            defer {
                context.deinitialize(count: 1)
                context.deallocate()
            }

            let pathsToWatch = [self.path] as CFArray
            let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
                guard let info else { return }
                let watcher = Unmanaged<FSWatcher>.fromOpaque(info).takeUnretainedValue()
                watcher.scheduleFire()
            }

            guard let stream = FSEventStreamCreate(
                kCFAllocatorDefault,
                callback,
                context,
                pathsToWatch,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                0.5,
                FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
            ) else { return }

            FSEventStreamSetDispatchQueue(stream, self.queue)
            FSEventStreamStart(stream)
            self.stream = stream
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, let stream = self.stream else { return }
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    private func scheduleFire() {
        // Already on `queue` from FSEvent dispatch.
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.onChange()
        }
        debounceWorkItem = item
        queue.asyncAfter(deadline: .now() + debounce, execute: item)
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
