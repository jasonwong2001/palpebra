import Foundation
import PalpebraCore
import Testing

struct ImageFillTests {
    private let laptop = CGSize(width: 3024, height: 1964)
    private let studioDisplay = CGSize(width: 5120, height: 2880)

    @Test func aLargePhotoDecodesAtTheSizeThatFillsTheScreen() {
        #expect(ImageFill.pixelSize(image: CGSize(width: 8064, height: 6048), screens: [laptop]) == 3024)
    }

    @Test func theMostDemandingScreenDecides() {
        let photo = CGSize(width: 8064, height: 6048)
        #expect(ImageFill.pixelSize(image: photo, screens: [laptop, studioDisplay]) == 5120)
    }

    @Test func narrowImagesKeepTheLengthThatCoversTheScreenWidth() {
        #expect(
            ImageFill.pixelSize(image: CGSize(width: 12000, height: 3000), screens: [CGSize(width: 2560, height: 1440)])
                == 5760)
        #expect(ImageFill.pixelSize(image: CGSize(width: 3000, height: 4000), screens: [laptop]) == 4000)
    }

    @Test func imagesAreNeverDecodedLargerThanTheyAre() {
        #expect(ImageFill.pixelSize(image: CGSize(width: 800, height: 600), screens: [studioDisplay]) == 800)
        #expect(ImageFill.pixelSize(image: CGSize(width: 8064, height: 6048), screens: []) == 8064)
        #expect(ImageFill.pixelSize(image: CGSize(width: 0, height: 0), screens: [laptop]) == 0)
    }
}
