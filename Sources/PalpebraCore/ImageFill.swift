import Foundation

/// Sizes a full-screen background so it fills every display without being decoded larger than shown.
package enum ImageFill: Sendable {
    /// The longest side, in pixels, that still fills the most demanding screen, never more than the image's own.
    /// Screens are in pixels; an image or screen list without size keeps the image's full size.
    package static func pixelSize(image: CGSize, screens: [CGSize]) -> Int {
        let longest = Double(max(image.width, image.height))
        guard image.width > 0, image.height > 0,
            let scale = screens.map({ Double(max($0.width / image.width, $0.height / image.height)) }).max()
        else { return DisplayNumber.nonnegativeInteger(longest.rounded()) }
        return DisplayNumber.nonnegativeInteger((longest * min(1, scale)).rounded())
    }
}
