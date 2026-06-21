import Combine
import CoreGraphics
import UIKit

struct StickerStyleRenderer {
    private static let maximumRenderDimension = 1664
    private let maskRenderer = StickerMaskRenderer()

    func styledSticker(from image: UIImage, style: StickerVisualStyle) throws -> UIImage {
        let preparedImage = try preparedImage(from: image)
        let source = style == .pixel ? try pixelated(preparedImage) : preparedImage
        let styled = try recoloredImage(from: source, style: style)
        return try maskRenderer.whiteBorderedSticker(from: styled)
    }

    static func renderedPNGData(from data: Data, style: StickerVisualStyle) -> Data? {
        guard let image = UIImage(data: data),
              let styledImage = try? StickerStyleRenderer().styledSticker(from: image, style: style) else {
            return nil
        }
        return styledImage.pngData()
    }

    private func preparedImage(from image: UIImage) throws -> UIImage {
        let normalized = try normalizedImage(from: image)
        guard let cgImage = normalized.cgImage else {
            throw StickerMaskError.cannotCreateOutput
        }
        let longestSide = max(cgImage.width, cgImage.height)
        guard longestSide > Self.maximumRenderDimension else {
            return normalized
        }

        let scale = CGFloat(Self.maximumRenderDimension) / CGFloat(longestSide)
        let targetSize = CGSize(
            width: max(1, CGFloat(cgImage.width) * scale),
            height: max(1, CGFloat(cgImage.height) * scale)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { context in
            context.cgContext.interpolationQuality = .high
            normalized.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private func normalizedImage(from image: UIImage) throws -> UIImage {
        guard image.imageOrientation != .up || image.cgImage == nil else {
            return image
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private func recoloredImage(from image: UIImage, style: StickerVisualStyle) throws -> UIImage {
        guard style != .whiteBorder else { return image }
        guard let cgImage = image.cgImage else {
            throw StickerMaskError.cannotCreateOutput
        }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else {
            throw StickerMaskError.cannotCreateOutput
        }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw StickerMaskError.cannotCreateOutput
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var luminanceMap = [UInt8](repeating: 0, count: width * height)
        var alphaMap = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                let mapIndex = y * width + x
                luminanceMap[mapIndex] = UInt8(
                    max(0, min(255, (CGFloat(pixels[index]) * 0.299 + CGFloat(pixels[index + 1]) * 0.587 + CGFloat(pixels[index + 2]) * 0.114).rounded()))
                )
                alphaMap[mapIndex] = pixels[index + 3]
            }
        }

        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                let alpha = alphaMap[y * width + x]
                guard alpha > 8 else { continue }

                let red = pixels[index]
                let green = pixels[index + 1]
                let blue = pixels[index + 2]
                let edgeStrength = edgeStrength(in: luminanceMap, alphaMap: alphaMap, width: width, height: height, x: x, y: y)
                let styled = styledColor(
                    red: red,
                    green: green,
                    blue: blue,
                    xRatio: CGFloat(x) / CGFloat(max(width - 1, 1)),
                    edgeStrength: edgeStrength,
                    style: style
                )

                pixels[index] = styled.red
                pixels[index + 1] = styled.green
                pixels[index + 2] = styled.blue
                pixels[index + 3] = alpha
            }
        }

        guard let outputContext = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ), let output = outputContext.makeImage() else {
            throw StickerMaskError.cannotCreateOutput
        }
        return UIImage(cgImage: output, scale: 1, orientation: .up)
    }

    private func pixelated(_ image: UIImage) throws -> UIImage {
        guard let cgImage = image.cgImage else {
            throw StickerMaskError.cannotCreateOutput
        }
        let width = cgImage.width
        let height = cgImage.height
        let blockSize = max(6, min(max(width, height) / 18, 18))
        let smallSize = CGSize(
            width: max(1, width / blockSize),
            height: max(1, height / blockSize)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false

        let smallImage = UIGraphicsImageRenderer(size: smallSize, format: format).image { context in
            context.cgContext.interpolationQuality = .none
            image.draw(in: CGRect(origin: .zero, size: smallSize))
        }

        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            context.cgContext.interpolationQuality = .none
            smallImage.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func styledColor(
        red: UInt8,
        green: UInt8,
        blue: UInt8,
        xRatio: CGFloat,
        edgeStrength: CGFloat,
        style: StickerVisualStyle
    ) -> (red: UInt8, green: UInt8, blue: UInt8) {
        let luminance = CGFloat(red) * 0.299 + CGFloat(green) * 0.587 + CGFloat(blue) * 0.114

        switch style {
        case .whiteBorder:
            return (red, green, blue)
        case .comicLine:
            if edgeStrength > 0.28 { return (18, 18, 18) }
            let value: UInt8 = luminance > 146 ? 248 : 214
            return (value, value, UInt8(min(255, Int(value) + 8)))
        case .pixel:
            let boosted = boost(red: red, green: green, blue: blue, saturation: 1.22, brightness: 1.04)
            return (
                quantized(boosted.red, levels: 5),
                quantized(boosted.green, levels: 5),
                quantized(boosted.blue, levels: 5)
            )
        case .neon:
            if edgeStrength > 0.18 {
                return xRatio < 0.5 ? (0, 245, 255) : (255, 48, 210)
            }
            return boost(red: red, green: green, blue: blue, saturation: 1.42, brightness: 0.9)
        case .duotoneStamp:
            if edgeStrength > 0.2 || luminance < 118 {
                return (26, 42, 96)
            }
            return (236, 55, 46)
        case .retroPoster:
            let warm = boost(red: red, green: green, blue: blue, saturation: 0.92, brightness: 1.06)
            return (
                quantized(UInt8(min(255, Int(warm.red) + 18)), levels: 4),
                quantized(UInt8(min(255, Int(warm.green) + 8)), levels: 4),
                quantized(UInt8(max(0, Int(warm.blue) - 14)), levels: 4)
            )
        case .pencilSketch:
            if edgeStrength > 0.16 {
                return (38, 38, 38)
            }
            let value = UInt8(max(176, min(252, luminance * 0.38 + 158)))
            return (value, value, value)
        case .brightPop:
            return boost(red: red, green: green, blue: blue, saturation: 1.72, brightness: 1.12)
        }
    }

    private func edgeStrength(in luminanceMap: [UInt8], alphaMap: [UInt8], width: Int, height: Int, x: Int, y: Int) -> CGFloat {
        let center = CGFloat(luminanceMap[y * width + x])
        var strongestDelta: CGFloat = 0
        let neighbors = [
            (max(0, x - 1), y),
            (min(width - 1, x + 1), y),
            (x, max(0, y - 1)),
            (x, min(height - 1, y + 1))
        ]
        for neighbor in neighbors {
            strongestDelta = max(strongestDelta, abs(center - CGFloat(luminanceMap[neighbor.1 * width + neighbor.0])))
        }
        let alphaEdge = CGFloat(255 - alphaMap[y * width + x]) / 255
        return max(strongestDelta / 255, alphaEdge)
    }

    private func boost(red: UInt8, green: UInt8, blue: UInt8, saturation: CGFloat, brightness: CGFloat) -> (red: UInt8, green: UInt8, blue: UInt8) {
        let luminance = CGFloat(red) * 0.299 + CGFloat(green) * 0.587 + CGFloat(blue) * 0.114
        let boostedRed = (luminance + (CGFloat(red) - luminance) * saturation) * brightness
        let boostedGreen = (luminance + (CGFloat(green) - luminance) * saturation) * brightness
        let boostedBlue = (luminance + (CGFloat(blue) - luminance) * saturation) * brightness
        return (clamped(boostedRed), clamped(boostedGreen), clamped(boostedBlue))
    }

    private func quantized(_ value: UInt8, levels: UInt8) -> UInt8 {
        let levelCount = max(levels, 2)
        let step = 255 / (levelCount - 1)
        return UInt8((Int(value) + Int(step) / 2) / Int(step) * Int(step))
    }

    private func clamped(_ value: CGFloat) -> UInt8 {
        UInt8(max(0, min(255, value.rounded())))
    }
}

@MainActor
final class StickerStyleRenderController: ObservableObject {
    @Published private(set) var renderingStyle: StickerVisualStyle?

    func render(sourceData: Data, style: StickerVisualStyle) async -> Data? {
        renderingStyle = style
        await Task.yield()
        defer { renderingStyle = nil }

        return await Task.detached(priority: .userInitiated) {
            StickerStyleRenderer.renderedPNGData(from: sourceData, style: style)
        }.value
    }
}
