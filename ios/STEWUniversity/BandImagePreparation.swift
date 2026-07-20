import Foundation
import ImageIO
import UIKit

enum BandImagePreparationError: LocalizedError {
    case unreadableImage

    var errorDescription: String? {
        "This image could not be prepared. Try choosing a different photo."
    }
}

enum BandImagePreparation {
    static func temporaryJPEG(from data: Data, maximumPixelSize: Int) throws -> URL {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                    kCGImageSourceShouldCacheImmediately: true,
                ] as CFDictionary
            ),
            let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.86)
        else {
            throw BandImagePreparationError.unreadableImage
        }
        let url = FileManager.default.temporaryDirectory
            .appending(path: "band-\(UUID().uuidString).jpg")
        try jpeg.write(to: url, options: .atomic)
        return url
    }
}
