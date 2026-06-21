import SwiftUI

struct StickerChip: View {
    var sticker: StickerItem
    var size: CGFloat = 76
    var isSelected = false

    var body: some View {
        ZStack {
            if let image = sticker.generatedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.04)
                    .shadow(color: StickifyTheme.softShadow, radius: 8, x: 0, y: 5)
            } else {
                RoundedRectangle(cornerRadius: size * 0.31, style: .continuous)
                    .fill(.white)
                    .shadow(color: StickifyTheme.softShadow, radius: 10, x: 0, y: 7)

                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(StickifyTheme.classicBlue.opacity(0.18))
                    .padding(size * 0.11)

                Image(systemName: sticker.symbolName)
                    .font(.system(size: size * 0.38, weight: .black))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(StickifyTheme.classicBlue)
            }

            if isSelected {
                RoundedRectangle(cornerRadius: size * 0.31, style: .continuous)
                    .stroke(StickifyTheme.classicBlue, lineWidth: 3)
            }
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(sticker.angle))
        .accessibilityLabel(sticker.fallbackName)
    }
}

private extension StickerItem {
    var generatedImage: UIImage? {
        guard let imageData else { return nil }
        return UIImage(data: imageData)
    }
}
