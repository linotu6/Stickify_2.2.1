import CoreImage
import UIKit
import Vision
import VisionKit
import XCTest
@testable import Stickify

final class StickerMaskRendererTests: XCTestCase {
    func testMaskApplicationCreatesTransparentBackgroundAndOpaqueSubject() throws {
        let source = try makeSourceImage()
        let mask = try makeMaskImage()

        let output = try StickerMaskRenderer().transparentSticker(from: source, mask: mask)

        let center = try rgbaPixel(in: output, x: 2, y: 2)
        let corner = try rgbaPixel(in: output, x: 0, y: 0)
        XCTAssertEqual(center.alpha, 255)
        XCTAssertEqual(corner.alpha, 0)
        XCTAssertNotNil(output.pngData())
    }

    func testFallbackStickerCreatesPNGWhenSegmentationIsUnavailable() throws {
        let source = makeUIImage(size: CGSize(width: 18, height: 12))

        let output = try StickerSegmentationService().fallbackSticker(from: source)

        XCTAssertFalse(output.pngData.isEmpty)
        XCTAssertEqual(output.isFallback, true)
    }

    func testFallbackStickerCutsOutSimpleForegroundWhenVisionIsUnavailable() throws {
        let source = makeForegroundOnWhiteUIImage(size: CGSize(width: 96, height: 96))

        let output = try StickerSegmentationService().fallbackSticker(from: source)

        let background = try rgbaPixel(in: output.image, x: 96, y: 96)
        let subject = try rgbaPixel(in: output.image, x: 256, y: 256)
        XCTAssertLessThan(background.alpha, 20)
        XCTAssertGreaterThan(subject.alpha, 220)
    }

    func testFallbackStickerAddsWhiteBorderAroundCutoutWithoutFillingCanvas() throws {
        let source = makeForegroundOnWhiteUIImage(size: CGSize(width: 96, height: 96))

        let output = try StickerSegmentationService().fallbackSticker(from: source)

        let subjectBounds = try pixelBounds(in: output.image) { pixel in
            pixel.alpha > 220 && pixel.blue > 150 && pixel.red < 80 && pixel.green < 180
        }
        let borderPixel = try rgbaPixel(
            in: output.image,
            x: max(0, Int(subjectBounds.minX.rounded(.down)) - 8),
            y: Int(subjectBounds.midY.rounded())
        )
        let unrelatedFramePixel = try rgbaPixel(in: output.image, x: 32, y: Int(subjectBounds.midY.rounded()))
        let corner = try rgbaPixel(in: output.image, x: 0, y: 0)

        XCTAssertGreaterThan(borderPixel.alpha, 220)
        XCTAssertGreaterThan(borderPixel.red, 235)
        XCTAssertGreaterThan(borderPixel.green, 235)
        XCTAssertGreaterThan(borderPixel.blue, 235)
        XCTAssertLessThan(unrelatedFramePixel.alpha, 20)
        XCTAssertLessThan(corner.alpha, 20)
    }

    func testEveryStickerVisualStylePreservesWhiteBorderAndTransparentCanvas() throws {
        let source = makeTransparentSubjectUIImage(size: CGSize(width: 128, height: 128))
        let renderer = StickerStyleRenderer()

        for style in StickerVisualStyle.allCases {
            let output = try renderer.styledSticker(from: source, style: style)

            let subjectBounds = try pixelBounds(in: output) { pixel in
                pixel.alpha > 220 && (pixel.red < 220 || pixel.green < 220 || pixel.blue < 220)
            }
            let borderPixel = try rgbaPixel(
                in: output,
                x: max(0, Int(subjectBounds.minX.rounded(.down)) - 2),
                y: Int(subjectBounds.midY.rounded())
            )
            let corner = try rgbaPixel(in: output, x: 0, y: 0)

            XCTAssertGreaterThan(borderPixel.alpha, 200, "\(style.rawValue) removed the sticker border.")
            XCTAssertGreaterThan(borderPixel.red, 220, "\(style.rawValue) did not preserve a white outer border.")
            XCTAssertGreaterThan(borderPixel.green, 220, "\(style.rawValue) did not preserve a white outer border.")
            XCTAssertGreaterThan(borderPixel.blue, 220, "\(style.rawValue) did not preserve a white outer border.")
            XCTAssertLessThan(corner.alpha, 20, "\(style.rawValue) filled the transparent canvas.")
        }
    }

    func testWhiteBorderUsesThickerSmoothStickerOutline() throws {
        let source = makeTransparentSubjectUIImage(size: CGSize(width: 128, height: 128))

        let output = try StickerMaskRenderer().whiteBorderedSticker(from: source)

        let subjectBounds = try pixelBounds(in: output) { pixel in
            pixel.alpha > 220 && pixel.blue > 150 && pixel.red < 80 && pixel.green < 180
        }
        let opaqueBounds = try pixelBounds(in: output) { pixel in
            pixel.alpha > 220
        }
        let leftBorderWidth = subjectBounds.minX - opaqueBounds.minX
        let rightBorderWidth = opaqueBounds.maxX - subjectBounds.maxX
        XCTAssertGreaterThanOrEqual(leftBorderWidth, 9)
        XCTAssertGreaterThanOrEqual(rightBorderWidth, 9)

        let solidBorderPixel = try rgbaPixel(
            in: output,
            x: max(0, Int(subjectBounds.minX.rounded(.down)) - 8),
            y: Int(subjectBounds.midY.rounded())
        )
        XCTAssertGreaterThan(solidBorderPixel.alpha, 230)
        XCTAssertGreaterThan(solidBorderPixel.red, 240)
        XCTAssertGreaterThan(solidBorderPixel.green, 240)
        XCTAssertGreaterThan(solidBorderPixel.blue, 240)

        let featherPixel = try rgbaPixel(
            in: output,
            x: max(0, Int(opaqueBounds.minX.rounded(.down)) - 1),
            y: Int(subjectBounds.midY.rounded())
        )
        XCTAssertGreaterThan(featherPixel.alpha, 0)
        XCTAssertLessThan(featherPixel.alpha, 230)
    }

    func testComicLineRenderingCapsLargeInputsForStability() throws {
        let source = makeTransparentSubjectUIImage(size: CGSize(width: 2400, height: 1800))

        let output = try StickerStyleRenderer().styledSticker(from: source, style: .comicLine)
        let cgImage = try XCTUnwrap(output.cgImage)

        XCTAssertLessThanOrEqual(max(cgImage.width, cgImage.height), 1900)
    }

    func testUserFacingMessageDoesNotExposeInferenceContextError() {
        let error = NSError(
            domain: "com.apple.Vision",
            code: 9,
            userInfo: [NSLocalizedDescriptionKey: "Could not create inference context"]
        )

        let message = StickerSegmentationService.userFacingMessage(for: error, usedFallback: true)

        XCTAssertFalse(message.localizedCaseInsensitiveContains("inference context"))
        XCTAssertFalse(message.contains("原图"))
        XCTAssertEqual(message, "已用本机简易抠图生成透明贴纸。复杂背景可能不完美，可以换一张主体更清晰的照片再试。")
    }

    func testPhotoSubjectDetectionFailureUsesRequiredFallbackMessage() {
        let error = NSError(
            domain: "com.apple.Vision",
            code: 9,
            userInfo: [NSLocalizedDescriptionKey: "Could not create inference context"]
        )

        let message = StickerSegmentationService.userFacingMessage(for: error, usedFallback: false)

        XCTAssertEqual(message, "Couldn’t find a clear object. Try another photo with a clearer subject.")
    }

    func testCameraCaptureFailurePointsUserToPhotoImportFallback() {
        XCTAssertEqual(
            LiveStickifyCameraError.captureFailed.localizedDescription,
            "相机没有成功拍到照片。你可以从相册选择图片继续生成透明贴纸。"
        )
    }

    func testNoSubjectDetectionMessageUsesRequiredFriendlyFallback() {
        XCTAssertEqual(
            StickerSubjectDetectionError.noForegroundFound.localizedDescription,
            "Couldn’t find a clear object. Try another photo with a clearer subject."
        )
    }

    func testSingleSubjectCandidateDoesNotMergeOtherVisionInstances() {
        let candidate = StickerSubjectCandidate(instanceIndex: 4, boundingBox: CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.5))

        XCTAssertEqual(candidate.instanceIndexes, IndexSet(integer: 4))
    }

    func testLocalFallbackCandidateIsNotSelectAll() {
        let candidate = StickerSubjectCandidate(localSubjectBoundingBox: CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.5))

        XCTAssertFalse(candidate.isSelectAll)
        XCTAssertEqual(candidate.title, "Subject")
    }

    func testCandidateOverlayLabelsUseSubjectNameOrInstanceIndex() {
        let localCandidate = StickerSubjectCandidate(localSubjectBoundingBox: CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.5))
        let visionCandidate = StickerSubjectCandidate(instanceIndex: 4, boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2))

        XCTAssertEqual(localCandidate.overlayLabel, "Subject")
        XCTAssertEqual(visionCandidate.overlayLabel, "4")
        XCTAssertEqual(visionCandidate.title, "Subject 4")
    }

    func testSelectionWithoutVisionObservationDoesNotOfferSelectAll() throws {
        let image = makeUIImage(size: CGSize(width: 200, height: 100))
        let cgImage = try XCTUnwrap(image.cgImage)
        let candidates = [
            StickerSubjectCandidate(localSubjectBoundingBox: CGRect(x: 0.1, y: 0.2, width: 0.2, height: 0.3)),
            StickerSubjectCandidate(localSubjectBoundingBox: CGRect(x: 0.5, y: 0.1, width: 0.3, height: 0.4))
        ]
        let diagnostics = StickerVisionDiagnostics(
            mode: .localFallback,
            originalPixelSize: CGSize(width: 200, height: 100),
            normalizedPixelSize: CGSize(width: 200, height: 100),
            originalOrientation: .up,
            visionOrientation: .up
        )

        let selection = StickerSubjectSelection(
            sourceImage: image,
            candidates: candidates,
            cgImage: cgImage,
            detectionMode: .localFallback,
            diagnostics: diagnostics
        )

        XCTAssertNil(selection.allInstancesCandidate)
    }

    func testProgrammaticVisionKitSelectionOffersSelectAllWithoutVisionObservation() throws {
        let image = makeUIImage(size: CGSize(width: 200, height: 100))
        let cgImage = try XCTUnwrap(image.cgImage)
        let candidates = [
            StickerSubjectCandidate(visionKitSubjectIndex: 0, boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.2, height: 0.3)),
            StickerSubjectCandidate(visionKitSubjectIndex: 1, boundingBox: CGRect(x: 0.5, y: 0.1, width: 0.3, height: 0.4))
        ]
        let diagnostics = StickerVisionDiagnostics(
            mode: .visionKit,
            originalPixelSize: CGSize(width: 200, height: 100),
            normalizedPixelSize: CGSize(width: 200, height: 100),
            originalOrientation: .up,
            visionOrientation: .up
        )

        let selection = StickerSubjectSelection(
            sourceImage: image,
            candidates: candidates,
            cgImage: cgImage,
            detectionMode: .visionKit,
            diagnostics: diagnostics
        )

        let allCandidate = try XCTUnwrap(selection.allInstancesCandidate)
        XCTAssertEqual(allCandidate.id, "select-all")
        XCTAssertEqual(allCandidate.instanceIndexes, IndexSet())
        XCTAssertEqual(allCandidate.boundingBox.origin.x, 0.1, accuracy: 0.001)
        XCTAssertEqual(allCandidate.boundingBox.origin.y, 0.1, accuracy: 0.001)
        XCTAssertEqual(allCandidate.boundingBox.width, 0.7, accuracy: 0.001)
        XCTAssertEqual(allCandidate.boundingBox.height, 0.4, accuracy: 0.001)
    }

    func testAutoCaptureSubjectSelectionMessageAsksUserToChooseMultipleSubjects() throws {
        let image = makeUIImage(size: CGSize(width: 200, height: 100))
        let cgImage = try XCTUnwrap(image.cgImage)
        let diagnostics = StickerVisionDiagnostics(
            mode: .vision,
            originalPixelSize: CGSize(width: 200, height: 100),
            normalizedPixelSize: CGSize(width: 200, height: 100),
            originalOrientation: .up,
            visionOrientation: .up
        )
        let selection = StickerSubjectSelection(
            sourceImage: image,
            candidates: [
                StickerSubjectCandidate(instanceIndex: 1, boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.4)),
                StickerSubjectCandidate(instanceIndex: 2, boundingBox: CGRect(x: 0.5, y: 0.2, width: 0.2, height: 0.3))
            ],
            cgImage: cgImage,
            observation: nil,
            detectionMode: .vision,
            diagnostics: diagnostics
        )

        let message = StickerSegmentationService.autoCaptureStatusMessage(for: selection)

        XCTAssertEqual(message, "Auto 找到 2 个可制作贴纸的主体，请点击要收集的物体")
    }

    func testAutoCaptureSubjectSelectionMessageWarnsWhenUsingRoughFallback() throws {
        let image = makeUIImage(size: CGSize(width: 200, height: 100))
        let cgImage = try XCTUnwrap(image.cgImage)
        let diagnostics = StickerVisionDiagnostics(
            mode: .localFallback,
            originalPixelSize: CGSize(width: 200, height: 100),
            normalizedPixelSize: CGSize(width: 200, height: 100),
            originalOrientation: .up,
            visionOrientation: .up
        )
        let selection = StickerSubjectSelection(
            sourceImage: image,
            candidates: [
                StickerSubjectCandidate(localSubjectBoundingBox: CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.4))
            ],
            cgImage: cgImage,
            detectionMode: .localFallback,
            diagnostics: diagnostics
        )

        let message = StickerSegmentationService.autoCaptureStatusMessage(for: selection)

        XCTAssertEqual(message, "Auto 只找到一个粗略主体，复杂背景可能需要手动重拍")
    }

    func testVisionInputPreparationDownscalesLargeImageBeforeRequest() throws {
        let source = makeUIImage(size: CGSize(width: 4_000, height: 2_000))

        let input = try StickerSegmentationService.preparedVisionInput(from: source, maxDimension: 1_536)

        XCTAssertEqual(input.cgImage.width, 1_536)
        XCTAssertEqual(input.cgImage.height, 768)
        XCTAssertEqual(input.sourceImage.imageOrientation, .up)
        XCTAssertEqual(input.originalPixelSize, CGSize(width: 4_000, height: 2_000))
        XCTAssertEqual(input.scale, 0.384, accuracy: 0.001)
    }

    func testVisionKitInputPreparationTriesFullResolutionBeforeDownscaledFallback() throws {
        let source = makeUIImage(size: CGSize(width: 4_000, height: 2_000))

        let inputs = try StickerSegmentationService.preparedVisionKitInputs(from: source)

        XCTAssertEqual(inputs.first?.cgImage.width, 4_000)
        XCTAssertEqual(inputs.first?.cgImage.height, 2_000)
        XCTAssertEqual(inputs.first?.scale, 1)
        XCTAssertEqual(inputs.last?.cgImage.width, 1_536)
        XCTAssertEqual(inputs.last?.cgImage.height, 768)
    }

    func testVisionInputPreparationAlsoTriesFullResolutionBeforeDownscaledFallback() throws {
        let source = makeUIImage(size: CGSize(width: 4_000, height: 2_000))

        let inputs = try StickerSegmentationService.preparedVisionInputs(from: source)

        XCTAssertEqual(inputs.first?.cgImage.width, 4_000)
        XCTAssertEqual(inputs.first?.cgImage.height, 2_000)
        XCTAssertEqual(inputs.first?.scale, 1)
        XCTAssertEqual(inputs.last?.cgImage.width, 1_536)
        XCTAssertEqual(inputs.last?.cgImage.height, 768)
    }

    @MainActor
    func testVisionKitAnalysisHostKeepsInteractionViewEligibleForAnalysis() throws {
        guard #available(iOS 17.0, *) else { return }
        let image = makeUIImage(size: CGSize(width: 120, height: 80))
        let interaction = ImageAnalysisInteraction()

        let host = VisionKitSubjectAnalysisHost(image: image, interaction: interaction)

        XCTAssertIdentical(host.imageView.image, image)
        XCTAssertEqual(host.imageView.bounds.size.width, image.size.width)
        XCTAssertEqual(host.imageView.bounds.size.height, image.size.height)
        XCTAssertTrue(host.imageView.interactions.contains { $0 === interaction })
        XCTAssertTrue(interaction.delegate === host)
        XCTAssertTrue(host.imageView.isUserInteractionEnabled)
        XCTAssertFalse(host.imageView.isHidden)
        XCTAssertEqual(host.imageView.alpha, 1)
        XCTAssertTrue(host.imageView.accessibilityElementsHidden)
        XCTAssertEqual(host.imageView.superview?.isUserInteractionEnabled, true)
        XCTAssertLessThan(host.imageView.superview?.alpha ?? 1, 0.02)
        XCTAssertLessThan(host.imageView.superview?.frame.minX ?? 0, -1_000)
    }

    @MainActor
    func testVisionKitAnalysisHostCanAttachAndDetachFromViewHierarchy() throws {
        guard #available(iOS 17.0, *) else { return }
        let image = makeUIImage(size: CGSize(width: 120, height: 80))
        let interaction = ImageAnalysisInteraction()
        let host = VisionKitSubjectAnalysisHost(image: image, interaction: interaction)
        let parent = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))

        host.attach(to: parent)

        XCTAssertTrue(host.imageView.isDescendant(of: parent))
        XCTAssertIdentical(host.contentView(for: interaction), host.imageView)

        host.detach()

        XCTAssertFalse(host.imageView.isDescendant(of: parent))
    }

    @MainActor
    func testVisionKitAnalysisHostProvidesImageBoundsAsContentsRect() throws {
        guard #available(iOS 17.0, *) else { return }
        let image = makeUIImage(size: CGSize(width: 120, height: 80))
        let interaction = ImageAnalysisInteraction()
        let host = VisionKitSubjectAnalysisHost(image: image, interaction: interaction)
        let delegate = host as ImageAnalysisInteractionDelegate

        XCTAssertEqual(host.contentsRect(for: interaction), CGRect(origin: .zero, size: image.size))
        XCTAssertIdentical(host.contentView(for: interaction), host.imageView)
        XCTAssertFalse(delegate.interaction(interaction, shouldBeginAt: CGPoint(x: 20, y: 20), for: .imageSubject))
    }

    func testFixturePhotoThatPhotosCanLiftProducesSelectableSubject() async throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("Subject lifting requires iOS 17") }
        let image = try fixtureDecodedPhotoImage()

        let selection: StickerSubjectSelection
        do {
            selection = try await StickerSegmentationService().detectPhotoSubjectCandidates(in: image)
        } catch {
            let message = (error as NSError).localizedDescription
            if isRunningInSimulator,
               message.localizedCaseInsensitiveContains("subjects was empty") {
                throw XCTSkip("iOS Simulator reports VisionKit.RemoveBackground as unsupported for this fixture; validate subject lifting on a real device.")
            }
            throw error
        }

        XCTAssertFalse(selection.candidates.isEmpty, selection.diagnostics.summary)
        if isRunningInSimulator,
           selection.diagnostics.summary.localizedCaseInsensitiveContains("inference context"),
           selection.detectionMode == .localFallback {
            throw XCTSkip("iOS Simulator cannot create the Vision foreground inference context for this fixture; validate subject lifting on a real device.")
        }
        XCTAssertNotEqual(selection.detectionMode, .localFallback, selection.diagnostics.summary)
    }

    func testFixturePhotoProducesSaliencyObjectWhenForegroundMaskFails() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("Saliency regression test requires iOS 17") }
        let image = try fixtureDecodedPhotoImage()
        let cgImage = try XCTUnwrap(image.cgImage)
        let request = VNGenerateObjectnessBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation))

        do {
            try handler.perform([request])
        } catch {
            let message = (error as NSError).localizedDescription
            if isRunningInSimulator,
               message.localizedCaseInsensitiveContains("espresso context") {
                throw XCTSkip("iOS Simulator cannot create the Vision saliency inference context for this fixture.")
            }
            throw error
        }

        let observation = try XCTUnwrap(request.results?.first)
        let salientObjects = observation.salientObjects ?? []
        XCTAssertFalse(salientObjects.isEmpty)
        XCTAssertTrue(salientObjects.contains { !$0.boundingBox.isEmpty && $0.boundingBox.width < 0.98 && $0.boundingBox.height < 0.98 })
    }

    func testFixtureHDRPhotoDecodesToVisibleSDRImage() throws {
        let image = try fixtureDecodedPhotoImage()

        let brightest = try brightestSampledRGB(in: image)

        XCTAssertGreaterThan(brightest, 12)
    }

    func testFixturePhotoDoesNotOfferFullFrameLocalFallbackAsSubject() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("Local photo fallback requires iOS 17") }
        let image = try fixtureDecodedPhotoImage()

        do {
            let selection = try StickerSegmentationService().localSubjectSelection(in: image)
            let candidate = try XCTUnwrap(selection.candidates.first)
            XCTAssertLessThan(candidate.boundingBox.width * candidate.boundingBox.height, 0.92)
            XCTAssertLessThan(candidate.boundingBox.width, 0.985)
            XCTAssertLessThan(candidate.boundingBox.height, 0.985)
            return
        } catch StickerSubjectDetectionError.noForegroundFound {
            return
        } catch {
            throw error
        }
    }

    func testVisionInputPreparationAppliesImageOrientationBeforeRequest() throws {
        let source = makeUIImage(size: CGSize(width: 40, height: 20))
        let rotated = try UIImage(cgImage: XCTUnwrap(source.cgImage), scale: 1, orientation: .right)

        let input = try StickerSegmentationService.preparedVisionInput(from: rotated, maxDimension: 100)

        XCTAssertEqual(input.cgImage.width, 20)
        XCTAssertEqual(input.cgImage.height, 40)
        XCTAssertEqual(input.sourceImage.imageOrientation, .up)
        XCTAssertEqual(input.originalOrientation, .right)
        XCTAssertEqual(input.visionOrientation, .up)
    }

    func testMaskBoundingBoxFindsVisiblePixelsInTopLeftCoordinates() throws {
        let mask = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 8), format: bitmapFormat).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 8))
            UIColor.white.setFill()
            context.fill(CGRect(x: 2, y: 3, width: 4, height: 2))
        }

        let box = try XCTUnwrap(StickerSegmentationService.normalizedVisibleBoundingBox(in: mask))

        XCTAssertEqual(box.origin.x, 0.2, accuracy: 0.001)
        XCTAssertEqual(box.origin.y, 0.375, accuracy: 0.001)
        XCTAssertEqual(box.width, 0.4, accuracy: 0.001)
        XCTAssertEqual(box.height, 0.25, accuracy: 0.001)
    }

    func testMaskStatsReportSmallValidObjectsInsteadOfDroppingThem() throws {
        let mask = try makeFloatMaskPixelBuffer(width: 20, height: 10, visibleRect: CGRect(x: 7, y: 4, width: 1, height: 2))

        let stats = try XCTUnwrap(StickerSegmentationService.visibleMaskStats(inMaskPixelBuffer: mask))

        XCTAssertEqual(stats.pixelCount, 2)
        XCTAssertEqual(stats.areaRatio, 0.01, accuracy: 0.001)
        XCTAssertEqual(stats.boundingBox.origin.x, 0.35, accuracy: 0.001)
        XCTAssertEqual(stats.boundingBox.origin.y, 0.4, accuracy: 0.001)
        XCTAssertEqual(stats.boundingBox.width, 0.05, accuracy: 0.001)
        XCTAssertEqual(stats.boundingBox.height, 0.2, accuracy: 0.001)
    }

    func testVisionFailureMessageDoesNotExposeFailingStageAndUnderlyingError() {
        let underlying = NSError(
            domain: "com.apple.Vision",
            code: 9,
            userInfo: [NSLocalizedDescriptionKey: "Could not create inference context"]
        )
        let failure = StickerVisionFailure(stage: .performRequest, underlyingError: underlying)

        let message = StickerSegmentationService.userFacingMessage(for: failure, usedFallback: false)

        XCTAssertFalse(message.contains("request.perform"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("inference context"))
        XCTAssertEqual(message, "Couldn’t find a clear object. Try another photo with a clearer subject.")
    }

    func testVisionKitEmptySubjectsMessageDoesNotExposeInternalAPIState() {
        let failure = StickerVisionFailure(stage: .readResults, detail: "ImageAnalysisInteraction.subjects was empty")

        let message = StickerSegmentationService.userFacingMessage(for: failure, usedFallback: false)

        XCTAssertFalse(message.localizedCaseInsensitiveContains("subjects"))
        XCTAssertEqual(message, "Couldn’t find a clear object. Try another photo with a clearer subject.")
    }

    func testOneComponentFloatMaskBoundingBoxFindsVisiblePixels() throws {
        let mask = try makeFloatMaskPixelBuffer(width: 10, height: 8, visibleRect: CGRect(x: 2, y: 3, width: 4, height: 2))

        let box = try XCTUnwrap(StickerSegmentationService.normalizedVisibleBoundingBox(inMaskPixelBuffer: mask))

        XCTAssertEqual(box.origin.x, 0.2, accuracy: 0.001)
        XCTAssertEqual(box.origin.y, 0.375, accuracy: 0.001)
        XCTAssertEqual(box.width, 0.4, accuracy: 0.001)
        XCTAssertEqual(box.height, 0.25, accuracy: 0.001)
    }

    func testLocalFallbackSubjectSelectionCreatesPreviewableCandidateForClearForeground() throws {
        let source = makeForegroundOnWhiteUIImage(size: CGSize(width: 160, height: 160))
        let service = StickerSegmentationService()

        let selection = try service.localSubjectSelection(in: source)
        let candidate = try XCTUnwrap(selection.candidates.first)
        let result = try service.transparentSticker(from: selection, candidate: candidate)

        XCTAssertEqual(selection.candidates.count, 1)
        XCTAssertGreaterThan(candidate.boundingBox.width, 0.2)
        XCTAssertGreaterThan(candidate.boundingBox.height, 0.3)
        XCTAssertFalse(result.pngData.isEmpty)
        XCTAssertTrue(result.isFallback)
        XCTAssertEqual(selection.detectionMode, .localFallback)
        XCTAssertTrue(selection.diagnostics.summary.contains("not multi-object Vision detection"))
        let corner = try rgbaPixel(in: result.image, x: 0, y: 0)
        XCTAssertLessThan(corner.alpha, 30)
    }

    private func makeSourceImage() throws -> CIImage {
        try XCTUnwrap(CIImage(image: makeUIImage(size: CGSize(width: 4, height: 4))))
    }

    private func makeMaskImage() throws -> CIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4), format: bitmapFormat)
        let image = renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
            UIColor.white.setFill()
            context.fill(CGRect(x: 1, y: 1, width: 2, height: 2))
        }
        return try XCTUnwrap(CIImage(image: image))
    }

    private var bitmapFormat: UIGraphicsImageRendererFormat {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return format
    }

    private func makeUIImage(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size, format: bitmapFormat)
        return renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func makeForegroundOnWhiteUIImage(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size, format: bitmapFormat)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: size.width * 0.31, y: size.height * 0.24, width: size.width * 0.38, height: size.height * 0.52))
        }
    }

    private func makeTransparentSubjectUIImage(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size, format: bitmapFormat)
        return renderer.image { context in
            UIColor.clear.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: size.width * 0.33, y: size.height * 0.24, width: size.width * 0.34, height: size.height * 0.52))
        }
    }

    private func makeFloatMaskPixelBuffer(width: Int, height: Int, visibleRect: CGRect) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_OneComponent32Float,
            nil,
            &pixelBuffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        let buffer = try XCTUnwrap(pixelBuffer)

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let baseAddress = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer))
        for y in 0..<height {
            let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float32.self)
            for x in 0..<width {
                row[x] = visibleRect.contains(CGPoint(x: x, y: y)) ? 1 : 0
            }
        }

        return buffer
    }

    private func fixtureImage() throws -> UIImage {
        let data = try fixturePhotoData()
        return try XCTUnwrap(UIImage(data: data), "Could not decode fixture image.")
    }

    private func fixtureDecodedPhotoImage() throws -> UIImage {
        let data = try fixturePhotoData()
        return try StickerSegmentationService.decodedPhotoImage(from: data)
    }

    private func fixturePhotoData() throws -> Data {
        let environment = ProcessInfo.processInfo.environment
        if let fixturePath = environment["STICKIFY_FIXTURE_IMAGE_PATH"] ?? environment["TEST_RUNNER_STICKIFY_FIXTURE_IMAGE_PATH"],
           !fixturePath.isEmpty {
            return try Data(contentsOf: URL(fileURLWithPath: fixturePath))
        }

        let bundle = Bundle(for: type(of: self))
        guard let fixtureURL = bundle.url(forResource: "IMG_6278", withExtension: "HEIC") else {
            throw XCTSkip("Bundle IMG_6278.HEIC or set STICKIFY_FIXTURE_IMAGE_PATH to run the real photo subject-lifting regression test.")
        }

        return try Data(contentsOf: fixtureURL)
    }

    private var isRunningInSimulator: Bool {
        ProcessInfo.processInfo.environment["SIMULATOR_UDID"] != nil
    }

    private func brightestSampledRGB(in image: UIImage) throws -> UInt8 {
        let cgImage = try XCTUnwrap(image.cgImage)
        var brightest: UInt8 = 0
        let xSamples = stride(from: 1, through: 5, by: 1).map { max(0, min(cgImage.width - 1, cgImage.width * $0 / 6)) }
        let ySamples = stride(from: 1, through: 5, by: 1).map { max(0, min(cgImage.height - 1, cgImage.height * $0 / 6)) }

        for y in ySamples {
            for x in xSamples {
                let pixel = try rgbaPixel(in: image, x: x, y: y)
                brightest = max(brightest, pixel.red, pixel.green, pixel.blue)
            }
        }

        return brightest
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
        let index = ((height - 1 - y) * width + x) * 4
        return (pixels[index], pixels[index + 1], pixels[index + 2], pixels[index + 3])
    }

    private func pixelBounds(
        in image: UIImage,
        matching predicate: ((red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)) -> Bool
    ) throws -> CGRect {
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

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1

        for y in 0..<height {
            for x in 0..<width {
                let index = ((height - 1 - y) * width + x) * 4
                let pixel = (red: pixels[index], green: pixels[index + 1], blue: pixels[index + 2], alpha: pixels[index + 3])
                if predicate(pixel) {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        XCTAssertGreaterThan(maxX, -1, "Expected to find matching pixels in sticker image.")
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
