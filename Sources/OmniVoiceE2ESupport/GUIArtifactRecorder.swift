import AppKit
import Foundation
import OmniVoiceCore

@MainActor
public final class GUIArtifactRecorder: AutomationEventSink {
    public let directoryURL: URL
    public let directoryPath: String

    private let screenshotsURL: URL
    private let framesURL: URL
    private let eventsURL: URL
    private let formatter = ISO8601DateFormatter()
    private var eventIndex = 0
    private var frameIndex = 0

    public init(directoryURL: URL) throws {
        self.directoryURL = directoryURL
        self.directoryPath = directoryURL.path
        screenshotsURL = directoryURL.appendingPathComponent("screenshots", isDirectory: true)
        framesURL = directoryURL.appendingPathComponent("frames", isDirectory: true)
        eventsURL = directoryURL.appendingPathComponent("events.jsonl")
        try FileManager.default.createDirectory(at: screenshotsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: framesURL, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: eventsURL.path) {
            FileManager.default.createFile(atPath: eventsURL.path, contents: nil)
        }
    }

    public func record(_ event: AutomationEvent) {
        eventIndex += 1
        var object: [String: Any] = [
            "index": eventIndex,
            "stage": event.stage,
            "timestamp": formatter.string(from: event.timestamp),
            "details": event.details
        ]
        if let errorKind = event.errorKind {
            object["error_kind"] = errorKind
        }
        if let surface = event.surface {
            object["surface"] = surfaceObject(surface)
        }
        if let data = event.screenshotPNGData {
            if event.stage.hasPrefix("gui_frame"),
               let fileName = writeFrame(data: data, event: event) {
                object["frame"] = "frames/\(fileName)"
            } else if let fileName = writeScreenshot(data: data, event: event) {
                object["screenshot"] = "screenshots/\(fileName)"
            }
        }
        appendEvent(object)
    }

    private func surfaceObject(_ surface: SurfaceDiagnosticSnapshot) -> [String: Any] {
        var object: [String: Any] = [
            "panel_type": surface.panelType,
            "level": surface.levelName,
            "is_visible": surface.isVisible
        ]
        if let windowNumber = surface.windowNumber {
            object["window_number"] = windowNumber
        }
        if let frame = surface.frame {
            object["frame"] = [
                "x": frame.origin.x,
                "y": frame.origin.y,
                "width": frame.width,
                "height": frame.height
            ]
        }
        return object
    }

    private func writeScreenshot(data: Data, event: AutomationEvent) -> String? {
        let surface = event.surface?.panelType ?? "surface"
        let fileName = String(
            format: "%03d-%@-%@.png",
            eventIndex,
            sanitized(event.stage),
            sanitized(surface)
        )
        let url = screenshotsURL.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
            return fileName
        } catch {
            return nil
        }
    }

    private func writeFrame(data: Data, event: AutomationEvent) -> String? {
        frameIndex += 1
        let surface = event.surface?.panelType ?? "surface"
        let fileName = String(
            format: "%05d-%@-%@.png",
            frameIndex,
            sanitized(event.stage),
            sanitized(surface)
        )
        let url = framesURL.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
            return fileName
        } catch {
            return nil
        }
    }

    private func appendEvent(_ object: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return
        }
        var line = data
        line.append(0x0A)
        do {
            let handle = try FileHandle(forWritingTo: eventsURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            try handle.close()
        } catch {
            try? line.write(to: eventsURL, options: .atomic)
        }
    }

    private func sanitized(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        var output = ""
        for scalar in value.unicodeScalars {
            if allowed.contains(scalar) {
                output.unicodeScalars.append(scalar)
            } else {
                output.append("-")
            }
        }
        let text = output.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return text.isEmpty ? "event" : String(text.prefix(64))
    }
}
