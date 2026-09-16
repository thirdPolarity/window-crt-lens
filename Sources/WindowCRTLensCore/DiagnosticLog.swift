import Foundation

/// Small, bounded local event journal. Callers supply metadata, never captured content.
public final class DiagnosticLog {
    public static let shared = DiagnosticLog(directory: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Window CRT Lens", isDirectory: true))

    public let directory: URL
    public let sessionID = UUID().uuidString
    public let fileURL: URL
    private let lock = NSLock()
    private let formatter = ISO8601DateFormatter()
    private let startedAt = ProcessInfo.processInfo.systemUptime
    private let maxBytes: Int
    private let maxFiles: Int
    private var handle: FileHandle?
    private var byteCount = 0
    private var failure: String?

    public init(directory: URL, maxBytes: Int = 2 * 1_024 * 1_024, maxFiles: Int = 60) {
        self.directory = directory
        self.maxBytes = maxBytes
        self.maxFiles = max(3, maxFiles)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        fileURL = directory.appendingPathComponent("lens-\(stamp)-\(ProcessInfo.processInfo.processIdentifier)-\(sessionID).jsonl")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
            try openFile()
            try prune()
        } catch { report(error) }
    }

    public var failureReason: String? {
        lock.lock(); defer { lock.unlock() }
        return failure
    }

    public func record(_ event: String, _ fields: [String: Any] = [:]) {
        lock.lock(); defer { lock.unlock() }
        guard failure == nil else { return }
        let entry: [String: Any] = [
            "timestamp": formatter.string(from: Date()),
            "uptimeSeconds": ProcessInfo.processInfo.systemUptime - startedAt,
            "session": sessionID, "pid": ProcessInfo.processInfo.processIdentifier,
            "event": event, "details": fields,
        ]
        do {
            var data = try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys])
            data.append(0x0A)
            if byteCount > 0, byteCount + data.count > maxBytes { try rotate() }
            try handle?.write(contentsOf: data)
            byteCount += data.count
        } catch { report(error) }
    }

    public func flush() {
        lock.lock(); defer { lock.unlock() }
        do { try handle?.synchronize() } catch { report(error) }
    }

    private func openFile() throws {
        guard FileManager.default.createFile(atPath: fileURL.path, contents: nil,
                                             attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        handle = try FileHandle(forWritingTo: fileURL)
        byteCount = 0
    }

    private func rotate() throws {
        try handle?.close()
        let fm = FileManager.default
        let previous = fileURL.appendingPathExtension("previous")
        if fm.fileExists(atPath: previous.path) { try fm.removeItem(at: previous) }
        try fm.moveItem(at: fileURL, to: previous)
        try openFile()
        try prune()
    }

    private func prune() throws {
        let fm = FileManager.default
        let files = try fm.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey])
            .filter { $0.lastPathComponent.hasPrefix("lens-") &&
                ($0.pathExtension == "jsonl" || $0.lastPathComponent.hasSuffix(".jsonl.previous")) &&
                (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) >
                      ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        for file in files.dropFirst(maxFiles) where file != fileURL {
            try fm.removeItem(at: file)
        }
    }

    private func report(_ error: Error) {
        let nsError = error as NSError
        failure = "\(nsError.domain) (\(nsError.code))"
        NSLog("[Window CRT Lens] Local diagnostics failed: %@", failure!)
    }

    deinit { try? handle?.close() }
}
