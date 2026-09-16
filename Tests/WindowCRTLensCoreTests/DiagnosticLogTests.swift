import Foundation
import XCTest
@testable import WindowCRTLensCore

final class DiagnosticLogTests: XCTestCase {
    func testConcurrentEventsRemainCompleteJSONAndShareOneLaunchID() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = DiagnosticLog(directory: folder)
        DispatchQueue.concurrentPerform(iterations: 100) { index in
            log.record("test", ["index": index])
        }
        log.flush()
        XCTAssertNil(log.failureReason)
        let lines = try String(contentsOf: log.fileURL).split(separator: "\n")
        XCTAssertEqual(lines.count, 100)
        let entries = try lines.map { try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]) }
        XCTAssertEqual(Set(entries.compactMap { $0["session"] as? String }), [log.sessionID])
        XCTAssertEqual(Set(entries.compactMap { ($0["details"] as? [String: Any])?["index"] as? Int }).count, 100)
        let permissions = try FileManager.default.attributesOfItem(atPath: log.fileURL.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
    }

    func testRotationKeepsRecentMarkerAndDoesNotTouchOtherFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = DiagnosticLog(directory: folder, maxBytes: 700)
        let unrelated = folder.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: unrelated)
        for i in 0..<50 { log.record("capture", ["index": i]) }
        log.record("user_marker", ["state": "mirror_glitch"])
        log.flush()
        XCTAssertNil(log.failureReason)
        XCTAssertTrue(try String(contentsOf: log.fileURL).contains("mirror_glitch"))
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 3)
        XCTAssertEqual(try String(contentsOf: unrelated), "keep")
        for file in files where file != unrelated {
            XCTAssertLessThanOrEqual(try Data(contentsOf: file).count, 700)
        }
    }

    func testEachRelaunchGetsADifferentLogAndOldSessionsAreBounded() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var sessions = Set<String>()
        for _ in 0..<8 {
            let log = DiagnosticLog(directory: folder, maxFiles: 3)
            sessions.insert(log.sessionID)
            log.record("launch")
            log.flush()
            XCTAssertNil(log.failureReason)
        }
        XCTAssertEqual(sessions.count, 8)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 3)
    }
}
