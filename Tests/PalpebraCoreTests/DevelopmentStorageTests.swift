#if DEBUG
    import Foundation
    import PalpebraCore
    import Testing

    struct DevelopmentStorageTests {
        @Test func developmentStorageIsUniqueAndCleansUp() throws {
            var first: DevelopmentStorage? = try DevelopmentStorage(onCleanupError: { Issue.record($0) })
            let second = try DevelopmentStorage(onCleanupError: { Issue.record($0) })
            defer { second.cleanup() }
            let firstStorage = try #require(first)
            let directory = firstStorage.directory
            let defaults = firstStorage.defaults
            #expect(directory != second.directory)
            #expect(directory.path.hasPrefix(FileManager.default.temporaryDirectory.path))
            #expect(AppSettings.load(from: defaults) == AppSettings())
            var settings = AppSettings()
            settings.breakSeconds = 85
            defaults.set(try JSONEncoder().encode(settings), forKey: DefaultsKey.settings)
            #expect(AppSettings.load(from: defaults).breakSeconds == 85)
            #expect(AppSettings.load(from: second.defaults) == AppSettings())
            let file = directory.appendingPathComponent("preview.json")
            try UsageHistory().save(to: file)
            #expect(FileManager.default.fileExists(atPath: file.path))
            firstStorage.cleanup()
            first = nil
            #expect(!FileManager.default.fileExists(atPath: directory.path))
            #expect(defaults.data(forKey: DefaultsKey.settings) == nil)
            #expect(FileManager.default.fileExists(atPath: second.directory.path))
        }

        @Test func everyDevelopmentEntryPointRequiresIsolatedStorage() {
            #expect(
                DevelopmentHooks.requiresIsolatedStorage(
                    arguments: ["Palpebra", "--render-previews", "/tmp/output"], environment: [:]))
            #expect(
                DevelopmentHooks.requiresIsolatedStorage(
                    arguments: ["Palpebra"], environment: ["PALPEBRA_SELFTEST": "1"]))
            #expect(
                DevelopmentHooks.requiresIsolatedStorage(
                    arguments: ["Palpebra"], environment: ["PALPEBRA_OPEN_MAIN": "1"]))
            #expect(!DevelopmentHooks.requiresIsolatedStorage(arguments: ["Palpebra"], environment: [:]))
            #expect(
                !DevelopmentHooks.requiresIsolatedStorage(
                    arguments: ["Palpebra"], environment: ["PALPEBRA_SELFTEST": "0"]))
        }
    }
#endif
