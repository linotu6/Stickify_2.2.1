import CoreImage
import UIKit

enum StickerMaskError: LocalizedError {
    case cannotCreateOutput
    case cannotCreatePNG

    var errorDescription: String? {
        switch self {
        case .cannotCreateOutput:
            "Stickify could not render the transparent sticker."
        case .cannotCreatePNG:
            "Stickify could not export the sticker as a PNG."
        }
    }
}

struct StickerMaskRenderer {
    private let context = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])

    /// Core Image mask pipeline:
    /// - white mask pixels keep the original image visible
    /// - black mask pixels reveal a transparent background
    /// - the resulting UIImage can be exported as a PNG with alpha
    func transparentSticker(from image: CIImage, mask: CIImage) throws -> UIImage {
        let extent = image.extent.integral
        let fittedMask = mask
            .transformed(by: CGAffineTransform(
                scaleX: extent.width / max(mask.extent.width, 1),
                y: extent.height / max(mask.extent.height, 1)
            ))
            .cropped(to: extent)

        let transparentBackground = CIImage(color: .clear).cropped(to: extent)
        let output = image
            .cropped(to: extent)
            .applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: transparentBackground,
                kCIInputMaskImageKey: fittedMask
            ])

        guard let cgImage = context.createCGImage(output, from: extent) else {
            throw StickerMaskError.cannotCreateOutput
        }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    func whiteBorderedSticker(from image: UIImage) throws -> UIImage {
        guard let cgImage = image.cgImage else {
            throw StickerMaskError.cannotCreateOutput
        }
        guard let visibleBounds = try visibleAlphaBounds(in: cgImage) else {
            return image
        }

        let borderWidth = Self.whiteBorderWidth(for: visibleBounds.size)
        let padding = ceil(borderWidth) + 2
        let source = CIImage(cgImage: cgImage)
        let outputExtent = CGRect(
            x: 0,
            y: 0,
            width: source.extent.width + padding * 2,
            height: source.extent.height + padding * 2
        ).integral
        let paddedSource = source.transformed(by: CGAffineTransform(translationX: padding, y: padding))
        let edgeSmoothingRadius = max(0.9, min(borderWidth * 0.1, 2.2))
        let dilatedAlpha = paddedSource
            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": max(0.6, min(borderWidth * 0.06, 1.8))])
            .applyingFilter("CIMorphologyMaximum", parameters: ["inputRadius": borderWidth])
            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": edgeSmoothingRadius])
            .cropped(to: outputExtent)
        let whiteBorder = dilatedAlpha
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0)
            ])
            .cropped(to: outputExtent)
        let output = paddedSource
            .applyingFilter("CISourceOverCompositing", parameters: [
                kCIInputBackgroundImageKey: whiteBorder
            ])
            .cropped(to: outputExtent)

        guard let borderedImage = context.createCGImage(output, from: outputExtent) else {
            throw StickerMaskError.cannotCreateOutput
        }
        return UIImage(cgImage: borderedImage, scale: 1, orientation: .up)
    }

    func pngData(from image: UIImage) throws -> Data {
        guard let data = image.pngData() else {
            throw StickerMaskError.cannotCreatePNG
        }
        return data
    }

    private static func whiteBorderWidth(for visibleSize: CGSize) -> CGFloat {
        let longestVisibleSide = max(visibleSize.width, visibleSize.height)
        return min(max((longestVisibleSide * 0.16).rounded(), 13), 52)
    }

    private func visibleAlphaBounds(in image: CGImage) throws -> CGRect? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw StickerMaskError.cannotCreateOutput
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1

        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                guard pixels[index + 3] > 12 else { continue }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
