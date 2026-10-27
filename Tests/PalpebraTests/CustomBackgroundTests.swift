import AppKit
import ImageIO
import PalpebraCore
import Testing
import UniformTypeIdentifiers

@testable import Palpebra

/// Images are generated in a disposable directory; the app's own background file is never read.
@MainActor
struct CustomBackgroundTests {
    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("palpebra-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// A solid image written with ImageIO, optionally tagged with an EXIF orientation.
    private func writeImage(
        width: Int, height: Int, type: UTType, orientation: Int = 1, to url: URL
    ) throws {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.4, green: 0.3, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(
            destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        try #require(CGImageDestinationFinalize(destination))
    }

    private func pixelSize(_ image: NSImage) throws -> CGSize {
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        return CGSize(width: cgImage.width, height: cgImage.height)
    }

    private var screens: [CGSize] {
        NSScreen.screens.map {
            CGSize(width: $0.frame.width * $0.backingScaleFactor, height: $0.frame.height * $0.backingScaleFactor)
        }
    }

    @Test func largePhotosAreDecodedAtTheSizeThatFillsTheScreens() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("photo.png")
        try writeImage(width: 9000, height: 6000, type: .png, to: source)
        let background = CustomBackground(fileURL: directory.appendingPathComponent("popup-background"))
        try await background.adopt(source)
        let size = try pixelSize(try #require(background.image))
        let expected = ImageFill.pixelSize(image: CGSize(width: 9000, height: 6000), screens: screens)
        #expect(Int(max(size.width, size.height)) == expected)
        #expect(abs(size.width / size.height - 1.5) < 0.01)

        let reloaded = CustomBackground(fileURL: directory.appendingPathComponent("popup-background"))
        await reloaded.loaded()
        #expect(try pixelSize(try #require(reloaded.image)) == size)
    }

    /// Decoding a large photo can take half a second, long enough to stall a break as it fades in, so the saved
    /// image loads in the background rather than while the popup is being built.
    @Test func theSavedImageLoadsInTheBackground() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("photo.jpg")
        try writeImage(width: 1200, height: 800, type: .jpeg, to: source)
        try await CustomBackground(fileURL: directory.appendingPathComponent("popup-background")).adopt(source)

        let reloaded = CustomBackground(fileURL: directory.appendingPathComponent("popup-background"))
        #expect(reloaded.image == nil)
        await reloaded.loaded()
        #expect(reloaded.image != nil)
    }

    /// A slow load of the old image must never replace one adopted or removed after it started.
    @Test func newerChoicesWinOverAnEarlierLoad() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = directory.appendingPathComponent("old.png")
        let new = directory.appendingPathComponent("new.jpg")
        try writeImage(width: 600, height: 600, type: .png, to: old)
        try writeImage(width: 400, height: 300, type: .jpeg, to: new)
        let file = directory.appendingPathComponent("popup-background")
        try await CustomBackground(fileURL: file).adopt(old)

        let adopting = CustomBackground(fileURL: file)
        try await adopting.adopt(new)
        await adopting.loaded()
        #expect(try pixelSize(try #require(adopting.image)) == CGSize(width: 400, height: 300))

        let removing = CustomBackground(fileURL: file)
        try await removing.remove()
        await removing.loaded()
        #expect(removing.image == nil)
    }

    @Test func rotatedPhotosAreDecodedUpright() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("portrait.jpg")
        // Stored landscape, shown portrait: orientation 6 turns the picture a quarter clockwise.
        try writeImage(width: 400, height: 300, type: .jpeg, orientation: 6, to: source)
        let background = CustomBackground(fileURL: directory.appendingPathComponent("popup-background"))
        try await background.adopt(source)
        let size = try pixelSize(try #require(background.image))
        #expect(size == CGSize(width: 300, height: 400))
    }

    @Test func filesThatAreNotImagesAreRejected() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("notes.txt")
        try Data("not an image".utf8).write(to: source)
        let background = CustomBackground(fileURL: directory.appendingPathComponent("popup-background"))
        await #expect(throws: (any Error).self) { try await background.adopt(source) }
        #expect(background.image == nil)
    }
}
