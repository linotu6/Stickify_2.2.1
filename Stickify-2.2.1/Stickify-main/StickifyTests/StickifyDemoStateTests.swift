import XCTest
import UIKit
@testable import Stickify

final class StickifyDemoStateTests: XCTestCase {
    func testStickerVisualStyleMVPContainsEightOptionsWithWhiteBorderDefault() {
        XCTAssertEqual(
            StickerVisualStyle.allCases,
            [
                .whiteBorder,
                .comicLine,
                .pixel,
                .neon,
                .duotoneStamp,
                .retroPoster,
                .pencilSketch,
                .brightPop
            ]
        )

        let sticker = StickerItem(name: "New", symbolName: "sparkles", category: .objects, color: .blue)

        XCTAssertEqual(sticker.visualStyle, .whiteBorder)
    }

    func testCloudHubUsesSevenLibrariesPlusPersistentCreateSlot() {
        let slots = StickifyDemoState.sample.cloudHubSlots(maxSlots: 8)

        XCTAssertEqual(slots.count, 8)
        XCTAssertEqual(slots.compactMap(\.library).count, 7)
        XCTAssertTrue(slots.last?.isCreateSlot == true)
    }

    func testAddingNamedCloudCreatesAnEmptyLibraryAndSelectsProvidedName() throws {
        var state = StickifyDemoState.sample

        let library = try XCTUnwrap(state.addCloud(named: "旅行灵感"))

        XCTAssertEqual(library.name, "旅行灵感")
        XCTAssertEqual(library.stickers.count, 0)
        XCTAssertEqual(state.libraries.last?.id, library.id)
    }

    func testAddingBlankCloudNameDoesNotCreateLibrary() {
        var state = StickifyDemoState.sample
        let libraryCount = state.libraries.count

        let library = state.addCloud(named: "   ")

        XCTAssertNil(library)
        XCTAssertEqual(state.libraries.count, libraryCount)
    }

    func testVaultColorSortUsesRainbowOrderBeforeNeutralColors() {
        let red = StickerItem(name: "Red", symbolName: "circle.fill", category: .objects, color: .red, dominantColorHex: 0xE52B1E)
        let yellow = StickerItem(name: "Yellow", symbolName: "circle.fill", category: .objects, color: .yellow, dominantColorHex: 0xFFCC00)
        let green = StickerItem(name: "Green", symbolName: "circle.fill", category: .objects, color: .green, dominantColorHex: 0x34C759)
        let blue = StickerItem(name: "Blue", symbolName: "circle.fill", category: .objects, color: .blue, dominantColorHex: 0x0056B8)
        let purple = StickerItem(name: "Purple", symbolName: "circle.fill", category: .objects, color: .purple, dominantColorHex: 0xAF52DE)
        let neutral = StickerItem(name: "Black", symbolName: "circle.fill", category: .objects, color: .black, dominantColorHex: 0x2D2926)
        let library = StickerLibrary(name: "Colors", stickers: [neutral, blue, yellow, purple, green, red])
        var state = StickifyDemoState.sample
        state.libraries = [library]

        let sortedNames = state.stickers(in: library.id, sortedBy: .color).map(\.name)

        XCTAssertEqual(sortedNames, ["Red", "Yellow", "Green", "Blue", "Purple", "Black"])
    }

    func testCloneAddsTenPointVisualOffsetToCopiedSticker() throws {
        var state = StickifyDemoState.sample
        let library = try XCTUnwrap(state.libraries.first)
        let original = try XCTUnwrap(library.stickers.first)

        state.clone(original, in: library)

        let copy = try XCTUnwrap(state.libraries.first?.stickers.first)
        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertEqual(copy.cloneOffset, original.cloneOffset + 10)
    }

    func testDollMachineModeRequiresGravityNoGapAndNoStacking() {
        var settings = PlaygroundScatterSettings()

        XCTAssertFalse(settings.isDollMachineMode)

        settings.gravityEnabled = true
        settings.hasGap = false
        settings.allowsStacking = false

        XCTAssertTrue(settings.isDollMachineMode)
    }

    func testSolidifyingSuperStickerFlattensCanvasBackIntoLibraryAndClearsStage() {
        var state = StickifyDemoState.sample
        state.addStickerToCanvas(state.shelf[0])
        state.addStickerToCanvas(state.shelf[1])

        state.solidifySuperSticker()

        XCTAssertEqual(state.superStickerCount, 1)
        XCTAssertEqual(state.libraries.first?.stickers.first?.source, .playground)
        XCTAssertEqual(state.shelf.first?.source, .playground)
        XCTAssertTrue(state.canvasItems.isEmpty)
    }

    func testSolidifyingSuperStickerStoresRenderedImageDataInsteadOfSystemLogoOnly() throws {
        var state = StickifyDemoState.sample
        state.addStickerToCanvas(state.shelf[0])
        state.addStickerToCanvas(state.shelf[1])

        state.solidifySuperSticker()

        let superSticker = try XCTUnwrap(state.libraries.first?.stickers.first)
        XCTAssertEqual(superSticker.source, .playground)
        XCTAssertNotNil(superSticker.imageData)
        XCTAssertNotEqual(superSticker.symbolName, "sparkles")
    }

    func testFusionRendererCreatesVisibleBridgeBetweenNearbyStickers() throws {
        let leftSticker = StickerItem(
            name: "Red Gel",
            symbolName: "circle.fill",
            category: .objects,
            color: .red,
            imageData: makeTransparentDotImage(color: .systemRed).pngData()
        )
        let rightSticker = StickerItem(
            name: "Blue Gel",
            symbolName: "circle.fill",
            category: .objects,
            color: .blue,
            imageData: makeTransparentDotImage(color: .systemBlue).pngData()
        )
        let items = [
            CanvasStickerItem(sticker: leftSticker, x: -24, y: 0, scale: 1, rotationDegrees: 0),
            CanvasStickerItem(sticker: rightSticker, x: 24, y: 0, scale: 1, rotationDegrees: 0)
        ]
        let canvasSize = CGSize(width: 160, height: 120)

        let stacked = try XCTUnwrap(SuperStickerRenderer.render(items: items, canvasSize: canvasSize, mode: .stack))
        let fused = try XCTUnwrap(SuperStickerRenderer.render(items: items, canvasSize: canvasSize, mode: .fusion))

        let stackedImage = try XCTUnwrap(stacked.cgImage)
        let fusedImage = try XCTUnwrap(fused.cgImage)
        let stackedGap = try rgbaPixel(in: stacked, x: stackedImage.width / 2, y: stackedImage.height / 2)
        let fusedBridge = try rgbaPixel(in: fused, x: fusedImage.width / 2, y: fusedImage.height / 2)
        XCTAssertLessThan(stackedGap.alpha, 30)
        XCTAssertGreaterThan(fusedBridge.alpha, 70)
        XCTAssertGreaterThan(fusedBridge.red, 70)
        XCTAssertGreaterThan(fusedBridge.blue, 70)
    }

    func testPhotoBackdropRendererUsesAspectFitInsteadOfCroppingWidePhotos() throws {
        let backdropData = try makeSplitBackdropImage(width: 200, height: 100).pngData().unwrap()

        let rendered = try XCTUnwrap(
            SuperStickerRenderer.render(
                items: [],
                canvasSize: CGSize(width: 100, height: 100),
                backdropImageData: backdropData,
                mode: .stack
            )
        )

        let renderedImage = try XCTUnwrap(rendered.cgImage)
        let leftEdge = try rgbaPixel(in: rendered, x: renderedImage.width / 20, y: renderedImage.height / 2)
        let rightEdge = try rgbaPixel(in: rendered, x: renderedImage.width * 19 / 20, y: renderedImage.height / 2)
        XCTAssertGreaterThan(leftEdge.red, 220)
        XCTAssertLessThan(leftEdge.blue, 60)
        XCTAssertGreaterThan(rightEdge.blue, 220)
        XCTAssertLessThan(rightEdge.red, 60)
    }

    func testPhotoStageExportCreatesCompositePNGWithoutAddingAppLibrarySticker() throws {
        var state = StickifyDemoState.sample
        let backdropData = try makeSplitBackdropImage(width: 200, height: 100).pngData().unwrap()
        let sticker = StickerItem(
            name: "Center Star",
            symbolName: "star.fill",
            category: .objects,
            color: .green,
            imageData: makeTransparentDotImage(color: .systemGreen).pngData()
        )
        state.shelf = [sticker]
        state.libraries = [StickerLibrary(name: "Generated", stickers: [sticker])]
        state.addStickerToCanvas(sticker)
        let originalShelfCount = state.shelf.count
        let originalLibraryCount = state.libraries[0].stickers.count

        let imageData = try XCTUnwrap(state.playgroundPhotoExportData(
            canvasSize: CGSize(width: 100, height: 100),
            backdropImageData: backdropData,
            mode: .stack
        ))

        let rendered = try XCTUnwrap(UIImage(data: imageData))
        let renderedImage = try XCTUnwrap(rendered.cgImage)
        let leftBackdrop = try rgbaPixel(in: rendered, x: renderedImage.width / 20, y: renderedImage.height / 2)
        let rightBackdrop = try rgbaPixel(in: rendered, x: renderedImage.width * 19 / 20, y: renderedImage.height / 2)
        XCTAssertGreaterThan(leftBackdrop.red, 180)
        XCTAssertGreaterThan(rightBackdrop.blue, 180)
        XCTAssertEqual(state.shelf.count, originalShelfCount)
        XCTAssertEqual(state.libraries[0].stickers.count, originalLibraryCount)
        XCTAssertFalse(state.canvasItems.isEmpty)
    }

    func testUpdatingStickerDetailsWritesThroughShelfLibrariesAndCanvas() throws {
        var state = StickifyDemoState.sample
        let sticker = state.shelf[0]
        let canvasItem = state.addStickerToCanvas(sticker)

        state.updateStickerDetails(id: sticker.id, name: "Updated Name", category: .fashion)

        let shelfSticker = try XCTUnwrap(state.shelf.first { $0.id == sticker.id })
        let librarySticker = try XCTUnwrap(state.libraries.flatMap(\.stickers).first { $0.id == sticker.id })
        let updatedCanvasItem = try XCTUnwrap(state.canvasItems.first { $0.id == canvasItem.id })
        XCTAssertEqual(shelfSticker.name, "Updated Name")
        XCTAssertEqual(shelfSticker.category, .fashion)
        XCTAssertEqual(librarySticker.name, "Updated Name")
        XCTAssertEqual(librarySticker.category, .fashion)
        XCTAssertEqual(updatedCanvasItem.sticker.name, "Updated Name")
        XCTAssertEqual(updatedCanvasItem.sticker.category, .fashion)
    }

    func testBlankStickerNameUpdateKeepsExistingNameButCanChangeCategory() throws {
        var state = StickifyDemoState.sample
        let sticker = state.shelf[0]

        state.updateStickerDetails(id: sticker.id, name: "   ", category: .people)

        let updated = try XCTUnwrap(state.shelf.first { $0.id == sticker.id })
        XCTAssertEqual(updated.name, sticker.name)
        XCTAssertEqual(updated.category, .people)
    }

    func testAddingGeneratedStickerStoresItAtTopOfShelfAndPrimaryLibrary() {
        var state = StickifyDemoState.sample
        let pngData = Data([0x89, 0x50, 0x4E, 0x47])

        let sticker = state.addGeneratedSticker(
            name: "Photo Cutout",
            imageData: pngData,
            source: .photoLibrary
        )

        XCTAssertEqual(state.shelf.first?.id, sticker.id)
        XCTAssertEqual(state.libraries.first?.stickers.first?.id, sticker.id)
        XCTAssertEqual(state.shelf.first?.imageData, pngData)
        XCTAssertEqual(state.shelf.first?.source, .photoLibrary)
    }

    func testAddingGeneratedStickerDefaultsToWhiteBorderAndKeepsOriginalImageDataForRestyling() throws {
        var state = StickifyDemoState.sample
        let originalData = try makeTransparentSubjectImage().pngData().unwrap()

        let sticker = state.addGeneratedSticker(
            name: "Photo Cutout",
            imageData: originalData,
            source: .photoLibrary,
            originalImageData: originalData
        )

        let saved = try XCTUnwrap(state.shelf.first { $0.id == sticker.id })
        XCTAssertEqual(saved.visualStyle, .whiteBorder)
        XCTAssertEqual(saved.originalImageData, originalData)
    }

    func testApplyingVisualStyleUpdatesShelfLibraryAndCanvasWithoutLosingOriginalSource() throws {
        var state = StickifyDemoState.sample
        state.shelf.removeAll()
        state.libraries = [StickerLibrary(name: "Generated", stickers: [])]
        let originalData = try makeTransparentSubjectImage().pngData().unwrap()
        let sticker = state.addGeneratedSticker(
            name: "Photo Cutout",
            imageData: originalData,
            source: .photoLibrary,
            originalImageData: originalData
        )
        let canvasItem = state.addStickerToCanvas(sticker)

        let changedCount = state.applyVisualStyle(.brightPop, to: [sticker.id])

        let shelfSticker = try XCTUnwrap(state.shelf.first { $0.id == sticker.id })
        let librarySticker = try XCTUnwrap(state.libraries.first?.stickers.first { $0.id == sticker.id })
        let canvasSticker = try XCTUnwrap(state.canvasItems.first { $0.id == canvasItem.id }?.sticker)
        XCTAssertEqual(changedCount, 1)
        XCTAssertEqual(shelfSticker.visualStyle, .brightPop)
        XCTAssertEqual(librarySticker.visualStyle, .brightPop)
        XCTAssertEqual(canvasSticker.visualStyle, .brightPop)
        XCTAssertEqual(shelfSticker.originalImageData, originalData)
        XCTAssertNotEqual(shelfSticker.imageData, originalData)
    }

    func testApplyingVisualStyleToLibraryBatchUpdatesEveryStickerInLibrary() throws {
        var state = StickifyDemoState.sample
        let firstData = try makeTransparentSubjectImage(color: .systemBlue).pngData().unwrap()
        let secondData = try makeTransparentSubjectImage(color: .systemRed).pngData().unwrap()
        let first = StickerItem(
            name: "First",
            symbolName: "photo.fill",
            category: .objects,
            color: .blue,
            imageData: firstData,
            originalImageData: firstData,
            source: .photoLibrary
        )
        let second = StickerItem(
            name: "Second",
            symbolName: "photo.fill",
            category: .objects,
            color: .red,
            imageData: secondData,
            originalImageData: secondData,
            source: .photoLibrary
        )
        state.shelf = [first, second]
        state.libraries = [StickerLibrary(name: "Generated", stickers: [first, second])]

        let changedCount = state.applyVisualStyle(.neon, in: state.libraries[0].id)

        XCTAssertEqual(changedCount, 2)
        XCTAssertTrue(state.shelf.allSatisfy { $0.visualStyle == .neon })
        XCTAssertTrue((state.libraries.first?.stickers ?? []).allSatisfy { $0.visualStyle == .neon })
    }

    func testFileStoreRestoresGeneratedStickersAfterRelaunch() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("plist")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = StickifyStateFileStore(fileURL: fileURL)
        var state = StickifyDemoState.sample
        let sourceData = try makeTransparentSubjectImage(color: .systemPurple).pngData().unwrap()
        let sticker = state.addGeneratedSticker(
            name: "Persistent Sticker",
            imageData: sourceData,
            source: .photoLibrary,
            originalImageData: sourceData,
            visualStyle: .brightPop
        )

        try store.save(state)
        let restored = try XCTUnwrap(try store.load())
        let restoredSticker = try XCTUnwrap(restored.libraries.first?.stickers.first)

        XCTAssertEqual(restoredSticker.id, sticker.id)
        XCTAssertEqual(restoredSticker.name, "Persistent Sticker")
        XCTAssertEqual(restoredSticker.source, .photoLibrary)
        XCTAssertEqual(restoredSticker.visualStyle, .brightPop)
        XCTAssertNotNil(restoredSticker.imageData)
        XCTAssertEqual(restoredSticker.originalImageData, sourceData)
    }

    func testRememberingDeleteCameraOriginalStopsAskingAfterRelaunch() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("plist")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = StickifyStateFileStore(fileURL: fileURL)
        var state = StickifyDemoState.sample

        state.applyCameraOriginalCacheChoice(.delete, rememberChoice: true)

        try store.save(state)
        let restored = try XCTUnwrap(try store.load())

        XCTAssertEqual(restored.cameraOriginalCachePreference, .deleteWithoutAsking)
        XCTAssertFalse(restored.cameraOriginalCachePreference.shouldAsk)
        XCTAssertEqual(restored.cameraOriginalCachePreference.defaultAction, .delete)
    }

    func testRememberingKeepCameraOriginalStopsAskingAfterRelaunch() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("plist")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = StickifyStateFileStore(fileURL: fileURL)
        var state = StickifyDemoState.sample

        state.applyCameraOriginalCacheChoice(.keep, rememberChoice: true)

        try store.save(state)
        let restored = try XCTUnwrap(try store.load())

        XCTAssertEqual(restored.cameraOriginalCachePreference, .keepWithoutAsking)
        XCTAssertFalse(restored.cameraOriginalCachePreference.shouldAsk)
        XCTAssertEqual(restored.cameraOriginalCachePreference.defaultAction, .keep)
    }

    func testKeepingCameraOriginalSavesOriginalPhotoOnlyOnce() {
        let originalData = Data([0xCA, 0xFE])
        var savedOriginals: [Data] = []
        var coordinator = CameraOriginalCacheCoordinator(
            preference: .askEveryTime,
            saveOriginalToPhotos: { savedOriginals.append($0) }
        )

        let preference = coordinator.handleOriginalPhotoData(
            originalData,
            action: .keep,
            rememberChoice: true
        )

        XCTAssertEqual(savedOriginals, [originalData])
        XCTAssertEqual(preference, .keepWithoutAsking)
    }

    func testDeletingCameraOriginalDoesNotSaveOriginalPhoto() {
        let originalData = Data([0xCA, 0xFE])
        var savedOriginals: [Data] = []
        var coordinator = CameraOriginalCacheCoordinator(
            preference: .askEveryTime,
            saveOriginalToPhotos: { savedOriginals.append($0) }
        )

        let preference = coordinator.handleOriginalPhotoData(
            originalData,
            action: .delete,
            rememberChoice: true
        )

        XCTAssertTrue(savedOriginals.isEmpty)
        XCTAssertEqual(preference, .deleteWithoutAsking)
    }

    func testStickerFlightStartsAtCaptureCenterWhenSubjectBoxIsUnavailable() {
        let path = StickerFlightPath(
            captureFrame: CGRect(x: 20, y: 100, width: 300, height: 400),
            targetFrame: CGRect(x: 260, y: 260, width: 80, height: 120),
            subjectBoundingBox: nil
        )

        XCTAssertEqual(path.start, CGPoint(x: 170, y: 300))
        XCTAssertEqual(path.target, CGPoint(x: 300, y: 320))
    }

    func testStickerFlightStartsAtSubjectCenterWhenBoundingBoxIsAvailable() {
        let path = StickerFlightPath(
            captureFrame: CGRect(x: 20, y: 100, width: 300, height: 400),
            targetFrame: CGRect(x: 260, y: 260, width: 80, height: 120),
            subjectBoundingBox: CGRect(x: 0.25, y: 0.5, width: 0.2, height: 0.1)
        )

        XCTAssertEqual(path.start, CGPoint(x: 125, y: 320))
        XCTAssertEqual(path.target, CGPoint(x: 300, y: 320))
    }

    @MainActor
    func testStyleRenderControllerExposesLoadingStateUntilRenderCompletes() async throws {
        let controller = StickerStyleRenderController()
        let sourceData = try makeTransparentSubjectImage(color: .systemOrange, size: CGSize(width: 480, height: 480)).pngData().unwrap()

        let task = Task {
            await controller.render(sourceData: sourceData, style: .comicLine)
        }
        await Task.yield()

        XCTAssertEqual(controller.renderingStyle, .comicLine)
        let renderedData = await task.value

        XCTAssertNotNil(renderedData)
        XCTAssertNil(controller.renderingStyle)
    }

    func testDeletingStickerRemovesItFromShelfLibrariesAndCanvas() {
        var state = StickifyDemoState.sample
        let sticker = state.shelf[0]
        state.addStickerToCanvas(sticker)

        state.deleteSticker(id: sticker.id)

        XCTAssertFalse(state.shelf.contains { $0.id == sticker.id })
        XCTAssertFalse(state.libraries.flatMap(\.stickers).contains { $0.id == sticker.id })
        XCTAssertFalse(state.canvasItems.contains { $0.sticker.id == sticker.id })
    }

    func testAddingStickerToCanvasCreatesAPlayablePlacement() {
        var state = StickifyDemoState.sample
        let sticker = state.shelf[1]

        let item = state.addStickerToCanvas(sticker)

        XCTAssertEqual(state.canvasItems.first?.id, item.id)
        XCTAssertEqual(state.canvasItems.first?.sticker.id, sticker.id)
        XCTAssertEqual(state.canvasItems.first?.scale, 1)
        XCTAssertEqual(state.canvasItems.first?.rotationDegrees, sticker.angle)
    }

    private func makeTransparentSubjectImage(
        color: UIColor = .systemBlue,
        size: CGSize = CGSize(width: 72, height: 72)
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.clear.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            color.setFill()
            context.fill(CGRect(x: 22, y: 16, width: 28, height: 40))
        }
    }

    private func makeTransparentDotImage(
        color: UIColor,
        size: CGSize = CGSize(width: 86, height: 86)
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.clear.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            color.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 31, y: 31, width: 24, height: 24))
        }
    }

    private func makeSplitBackdropImage(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor(red: 1, green: 0, blue: 0, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
            UIColor(red: 0, green: 0, blue: 1, alpha: 1).setFill()
            context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height))
        }
    }

    private func rgbaPixel(in image: UIImage, x: Int, y: Int) throws -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        try XCTUnwrap(context).draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let boundedX = min(max(x, 0), width - 1)
        let boundedY = min(max(y, 0), height - 1)
        let index = ((height - 1 - boundedY) * width + boundedX) * 4
        return (pixels[index], pixels[index + 1], pixels[index + 2], pixels[index + 3])
    }
}

private extension Optional {
    func unwrap(file: StaticString = #filePath, line: UInt = #line) throws -> Wrapped {
        try XCTUnwrap(self, file: file, line: line)
    }
}
