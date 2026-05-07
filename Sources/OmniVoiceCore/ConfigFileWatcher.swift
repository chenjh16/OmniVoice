import Foundation
import Dispatch
import Darwin

public final class ConfigFileWatcher: @unchecked Sendable {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "\(AppConstants.bundleIdentifier).config-file-watcher")
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var debounceWorkItem: DispatchWorkItem?

    public var onChange: (@Sendable () -> Void)?

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    deinit {
        stop()
    }

    public func start() {
        stop()
        let directoryURL = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        startDirectorySource(directoryURL: directoryURL)
        refreshFileSource()
    }

    public func stop() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        directorySource?.cancel()
        directorySource = nil
        fileSource?.cancel()
        fileSource = nil
    }

    private func startDirectorySource(directoryURL: URL) {
        let fd = open(directoryURL.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend, .attrib],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.refreshFileSource()
            self?.scheduleDebouncedChange()
        }
        source.setCancelHandler {
            close(fd)
        }
        directorySource = source
        source.resume()
    }

    private func refreshFileSource() {
        fileSource?.cancel()
        fileSource = nil
        let fd = open(fileURL.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend, .attrib],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.scheduleDebouncedChange()
        }
        source.setCancelHandler {
            close(fd)
        }
        fileSource = source
        source.resume()
    }

    private func scheduleDebouncedChange() {
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.onChange?()
        }
        debounceWorkItem = workItem
        queue.asyncAfter(deadline: .now() + .milliseconds(500), execute: workItem)
    }
}
