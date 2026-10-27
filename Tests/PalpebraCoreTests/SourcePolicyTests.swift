import Foundation
import Testing

struct SourcePolicyTests {
    private func sources() throws -> [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let directory = root.appendingPathComponent("Sources", isDirectory: true)
        let enumerator = try #require(
            FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        )
        let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        try #require(!files.isEmpty, "No Swift sources found under \(directory.path)")
        return files
    }

    @Test func sourcesAreEnglishOnly() throws {
        for file in try sources() {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(
                source.range(of: "\\p{sc=Han}", options: .regularExpression) == nil,
                "Unexpected Han script in \(file.path)"
            )
            #expect(!source.contains("L.t("), "Bilingual helper in \(file.path)")
            #expect(!source.contains("Locale.preferredLanguages"), "Language switching in \(file.path)")
        }
    }

    @Test func sourcesHaveNoNetworking() throws {
        let forbidden = [
            "URLSession", "URLRequest", "NWConnection", "NWListener", "NWPathMonitor",
            "import Network", "import WebKit", "CFSocket", "CFStream", "getaddrinfo", "socket(",
        ]
        for file in try sources() {
            let source = try String(contentsOf: file, encoding: .utf8)
            for token in forbidden {
                #expect(!source.contains(token), "Networking token \(token) in \(file.path)")
            }
        }
    }

    @Test func detectionNeverCapturesScreensOrMonitorsIndividualEvents() throws {
        let forbidden = [
            "CGWindowListCreateImage", "AXIsProcessTrusted", "addGlobalMonitorForEvents", "addLocalMonitorForEvents",
        ]
        for file in try sources() {
            let source = try String(contentsOf: file, encoding: .utf8)
            for token in forbidden {
                #expect(!source.contains(token), "Permission-requiring detection token \(token) in \(file.path)")
            }
        }
    }
}
