import Foundation

/// Every persistence test gets a disposable directory, including failure paths.
func withTemporaryDirectory<T>(_ operation: (URL) throws -> T) throws -> T {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("palpebra-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    return try operation(directory)
}
