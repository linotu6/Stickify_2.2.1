import CoreImage
import ImageIO
import os
import UIKit
import Vision
@preconcurrency import VisionKit

struct GeneratedStickerResult {
    var image: UIImage
    var pngData: Data
    var originalImageData: Data? = nil
    var isFallback = false
    var message: String?
}

struct StickerVisionInput {
    var sourceImage: UIImage
    var cgImage: CGImage
    var originalPixelSize: CGSize
    var originalOrientation: UIImage.Orientation
    var visionOrientation: CGImagePropertyOrientation
    var scale: CGFloat
}

@available(iOS 17.0, *)
@MainActor
final class VisionKitSubjectAnalysisHost {
    private let containerView = UIView()
    let imageView: UIImageView
    let interaction: ImageAnalysisInteraction

    init(image: UIImage, interaction: ImageAnalysisInteraction) {
        self.imageView = UIImageView(image: image)
        self.interaction = interaction

        containerView.frame = CGRect(x: -20_000, y: -20_000, width: 1, height: 1)
        containerView.clipsToBounds = false
        containerView.alpha = 0.01
        containerView.isHidden = false
        containerView.isUserInteractionEnabled = true
        containerView.accessibilityElementsHidden = true

        imageView.frame = CGRect(origin: .zero, size: image.size)
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.alpha = 1
        imageView.isHidden = false
        imageView.isUserInteractionEnabled = true
        imageView.accessibilityElementsHidden = true
        containerView.addSubview(imageView)
        interaction.delegate = self
        imageView.addInteraction(interaction)
    }

    var isAttachedToWindow: Bool {
        imageView.window != nil
    }

    @discardableResult
    func attachToActiveWindow() -> Bool {
        guard let window = Self.activeWindow else {
            return false
        }

        attach(to: window)
        return true
    }

    func attach(to view: UIView) {
        guard containerView.superview !== view else { return }
        containerView.removeFromSuperview()
        view.addSubview(containerView)
    }

    func detach() {
        containerView.removeFromSuperview()
    }

    private static var activeWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .filter { $0.activationState == .foregroundActive }
                .flatMap(\.windows)
                .first { !$0.isHidden && $0.alpha > 0 }
    }
}

@available(iOS 17.0, *)
extension VisionKitSubjectAnalysisHost: ImageAnalysisInteractionDelegate {
    func interaction(
        _ interaction: ImageAnalysisInteraction,
        shouldBeginAt point: CGPoint,
        for interactionType: ImageAnalysisInteraction.InteractionTypes
    ) -> Bool {
        false
    }

    func contentsRect(for interaction: ImageAnalysisInteraction) -> CGRect {
        imageView.bounds
    }

    func contentView(for interaction: ImageAnalysisInteraction) -> UIView? {
        imageView
    }
}

enum StickerVisionStage: String {
    case prepareImage = "image preparation"
    case performRequest = "request.perform"
    case readResults = "result parsing"
    case generateMask = "mask generation"
    case parseMask = "mask pixel parsing"
    case filterCandidate = "candidate filtering"
}

struct StickerVisionFailure: LocalizedError {
    var stage: StickerVisionStage
    var instanceIndex: Int?
    var underlyingError: Error?
    var detail: String?

    var errorDescription: String? {
        var message = "Vision foreground extraction failed during \(stage.rawValue)"
        if let instanceIndex {
            message += " for instance \(instanceIndex)"
        }
        if let detail, !detail.isEmpty {
            message += ": \(detail)"
        } else if let underlyingError {
            message += ": \((underlyingError as NSError).localizedDescription)"
        }
        return message
    }
}

struct StickerMaskStats: Equatable {
    var pixelCount: Int
    var boundingBox: CGRect
    var areaRatio: CGFloat
}

enum StickerCandidateDecision: Equatable {
    case accepted
    case rejected(String)

    var summary: String {
        switch self {
        case .accepted:
            "accepted"
        case .rejected(let reason):
            "rejected: \(reason)"
        }
    }
}

struct StickerVisionInstanceDiagnostic: Equatable {
    var instanceIndex: Int
    var maskPixelCount: Int
    var boundingBox: CGRect?
    var areaRatio: CGFloat
    var decision: StickerCandidateDecision

    var summary: String {
        let box = boundingBox.map { "bbox=\($0.debugSummary)" } ?? "bbox=nil"
        return "instance=\(instanceIndex) pixels=\(maskPixelCount) areaRatio=\(String(format: "%.5f", areaRatio)) \(box) \(decision.summary)"
    }
}

enum StickerSubjectDetectionMode: Equatable {
    case visionKit
    case vision
    case localFallback
}

struct StickerVisionDiagnostics: Equatable {
    var mode: StickerSubjectDetectionMode
    var originalPixelSize: CGSize
    var normalizedPixelSize: CGSize
    var originalOrientation: UIImage.Orientation
    var visionOrientation: CGImagePropertyOrientation
    var events: [String] = []
    var instances: [StickerVisionInstanceDiagnostic] = []

    var summary: String {
        var lines = [
            "mode=\(mode)",
            "original=\(Int(originalPixelSize.width))x\(Int(originalPixelSize.height)) orientation=\(originalOrientation)",
            "visionInput=\(Int(normalizedPixelSize.width))x\(Int(normalizedPixelSize.height)) orientation=\(visionOrientation)"
        ]
        lines.append(contentsOf: events)
        lines.append(contentsOf: instances.map(\.summary))
        return lines.joined(separator: " | ")
    }
}

enum StickerSubjectDetectionError: LocalizedError {
    case invalidImage
    case foregroundMaskUnavailable
    case noForegroundFound

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            "Stickify couldn’t read this photo. Try another image."
        case .foregroundMaskUnavailable:
            "Automatic subject selection is not available on this device."
        case .noForegroundFound:
            "Couldn’t find a clear object. Try another photo with a clearer subject."
        }
    }
}

struct StickerSubjectCandidate: Identifiable, Equatable {
    var id: String
    var instanceIndex: Int?
    var instanceIndexes: IndexSet
    var boundingBox: CGRect
    var title: String
    var isSelectAll: Bool
    var overlayLabelOverride: String?

    init(instanceIndex: Int, boundingBox: CGRect) {
        self.id = "instance-\(instanceIndex)"
        self.instanceIndex = instanceIndex
        self.instanceIndexes = IndexSet(integer: instanceIndex)
        self.boundingBox = boundingBox
        self.title = "Subject \(instanceIndex)"
        self.isSelectAll = false
        self.overlayLabelOverride = nil
    }

    init(visionKitSubjectIndex: Int, boundingBox: CGRect) {
        self.id = "visionkit-subject-\(visionKitSubjectIndex)"
        self.instanceIndex = nil
        self.instanceIndexes = []
        self.boundingBox = boundingBox
        self.title = "Subject \(visionKitSubjectIndex + 1)"
        self.isSelectAll = false
        self.overlayLabelOverride = "\(visionKitSubjectIndex + 1)"
    }

    init(localSubjectBoundingBox boundingBox: CGRect) {
        self.id = "local-subject"
        self.instanceIndex = nil
        self.instanceIndexes = []
        self.boundingBox = boundingBox
        self.title = "Subject"
        self.isSelectAll = false
        self.overlayLabelOverride = nil
    }

    private init(id: String, instanceIndexes: IndexSet, boundingBox: CGRect, title: String) {
        self.id = id
        self.instanceIndex = nil
        self.instanceIndexes = instanceIndexes
        self.boundingBox = boundingBox
        self.title = title
        self.isSelectAll = true
        self.overlayLabelOverride = nil
    }

    static func selectAll(instanceIndexes: IndexSet, boundingBox: CGRect) -> StickerSubjectCandidate {
        StickerSubjectCandidate(
            id: "select-all",
            instanceIndexes: instanceIndexes,
            boundingBox: boundingBox,
            title: "Select All"
        )
    }

    var overlayLabel: String {
        if let overlayLabelOverride {
            return overlayLabelOverride
        }
        if isSelectAll {
            return "All"
        }
        if let instanceIndex {
            return "\(instanceIndex)"
        }
        return title
    }

}

@available(iOS 17.0, *)
struct StickerSubjectSelection: Identifiable, @unchecked Sendable {
    var id = UUID()
    var sourceImage: UIImage
    var sourceOriginalPhotoData: Data?
    var candidates: [StickerSubjectCandidate]
    fileprivate var cgImage: CGImage
    fileprivate var observation: VNInstanceMaskObservation?
    fileprivate var precomputedResults: [String: GeneratedStickerResult] = [:]
    var detectionMode: StickerSubjectDetectionMode = .vision
    var diagnostics: StickerVisionDiagnostics

    init(
        id: UUID = UUID(),
        sourceImage: UIImage,
        sourceOriginalPhotoData: Data? = nil,
        candidates: [StickerSubjectCandidate],
        cgImage: CGImage,
        observation: VNInstanceMaskObservation? = nil,
        precomputedResults: [String: GeneratedStickerResult] = [:],
        detectionMode: StickerSubjectDetectionMode = .vision,
        diagnostics: StickerVisionDiagnostics
    ) {
        self.id = id
        self.sourceImage = sourceImage
        self.sourceOriginalPhotoData = sourceOriginalPhotoData
        self.candidates = candidates
        self.cgImage = cgImage
        self.observation = observation
        self.precomputedResults = precomputedResults
        self.detectionMode = detectionMode
        self.diagnostics = diagnostics
    }

    var sourceSize: CGSize {
        CGSize(width: cgImage.width, height: cgImage.height)
    }

    var allInstances: IndexSet {
        observation?.allInstances ?? []
    }

    var allInstancesCandidate: StickerSubjectCandidate? {
        guard (observation != nil || detectionMode == .visionKit), candidates.count > 1 else { return nil }
        let union = candidates.reduce(CGRect.null) { partialResult, candidate in
            partialResult.union(candidate.boundingBox)
        }
        return StickerSubjectCandidate.selectAll(
            instanceIndexes: detectionMode == .visionKit ? [] : allInstances,
            boundingBox: union
        )
    }
}

struct StickerSegmentationService {
    private let renderer = StickerMaskRenderer()
    private static let maskContext = CIContext()
    private static let visionContext = CIContext()
    private static let visionLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.sirius.Stickify", category: "StickerVision")
    private static let visionMaxDimension: CGFloat = 1_536

    @available(iOS 17.0, *)
    func transparentSticker(from image: UIImage) throws -> GeneratedStickerResult {
        let selection = try detectSubjectCandidates(in: image)
        guard let firstCandidate = selection.candidates.first else {
            throw StickerSubjectDetectionError.noForegroundFound
        }
        return try transparentSticker(from: selection, candidate: firstCandidate)
    }

    @available(iOS 17.0, *)
    func detectSubjectCandidates(in image: UIImage) throws -> StickerSubjectSelection {
        do {
            let selection = try visionSubjectSelection(in: image)
            Self.logDiagnostics(selection.diagnostics)
            return selection
        } catch {
            let visionFailure = error as? StickerVisionFailure ?? StickerVisionFailure(stage: .performRequest, underlyingError: error)
            Self.logVisionFailure(visionFailure)
            do {
                var fallback = try localSubjectSelection(in: image)
                fallback.diagnostics.events.insert("Vision failed before local fallback: \(visionFailure.localizedDescription)", at: 0)
                Self.logDiagnostics(fallback.diagnostics)
                return fallback
            } catch let fallbackError {
                Self.visionLogger.error("Local fallback also failed: \(String(describing: fallbackError), privacy: .public)")
                throw visionFailure
            }
        }
    }

    @available(iOS 17.0, *)
    func detectPhotoSubjectCandidates(in image: UIImage) async throws -> StickerSubjectSelection {
        do {
            let selection = try await Task.detached(priority: .userInitiated) {
                try StickerSegmentationService().visionSubjectSelection(in: image)
            }.value
            Self.logDiagnostics(selection.diagnostics)
            return selection
        } catch {
            let visionFailure = error as? StickerVisionFailure ?? StickerVisionFailure(stage: .performRequest, underlyingError: error)
            Self.logVisionFailure(visionFailure)

            do {
                var selection = try await visionKitSubjectSelection(in: image)
                selection.diagnostics.events.insert("Vision failed before programmatic VisionKit fallback: \(visionFailure.localizedDescription)", at: 0)
                Self.logDiagnostics(selection.diagnostics)
                return selection
            } catch {
                let visionKitFailure = error as? StickerVisionFailure ?? StickerVisionFailure(stage: .performRequest, underlyingError: error)
                Self.logVisionFailure(visionKitFailure)
                do {
                    var fallback = try await Task.detached(priority: .userInitiated) {
                        try StickerSegmentationService().localSubjectSelection(in: image)
                    }.value
                    fallback.diagnostics.events.insert("VisionKit failed before local fallback: \(visionKitFailure.localizedDescription)", at: 0)
                    fallback.diagnostics.events.insert("Vision failed before VisionKit fallback: \(visionFailure.localizedDescription)", at: 0)
                    Self.logDiagnostics(fallback.diagnostics)
                    return fallback
                } catch let fallbackError {
                    Self.visionLogger.error("Local fallback after VisionKit also failed: \(String(describing: fallbackError), privacy: .public)")
                    throw visionKitFailure
                }
            }
        }
    }

    @available(iOS 17.0, *)
    @MainActor
    private func visionKitSubjectSelection(in image: UIImage) async throws -> StickerSubjectSelection {
        guard ImageAnalyzer.isSupported else {
            throw StickerVisionFailure(stage: .performRequest, detail: "ImageAnalyzer.isSupported was false on this runtime")
        }

        let inputs: [StickerVisionInput]
        do {
            inputs = try Self.preparedVisionKitInputs(from: image)
        } catch {
            throw StickerVisionFailure(stage: .prepareImage, underlyingError: error)
        }

        var firstFailure: StickerVisionFailure?
        for input in inputs {
            do {
                return try await visionKitSubjectSelection(using: input)
            } catch {
                let failure = error as? StickerVisionFailure ?? StickerVisionFailure(stage: .performRequest, underlyingError: error)
                firstFailure = firstFailure ?? failure
                Self.logVisionFailure(failure)
            }
        }

        throw firstFailure ?? StickerVisionFailure(stage: .readResults, detail: "Programmatic VisionKit returned no usable subjects")
    }

    @available(iOS 17.0, *)
    @MainActor
    private func visionKitSubjectSelection(using input: StickerVisionInput) async throws -> StickerSubjectSelection {
        var diagnostics = StickerVisionDiagnostics(
            mode: .visionKit,
            originalPixelSize: input.originalPixelSize,
            normalizedPixelSize: CGSize(width: input.cgImage.width, height: input.cgImage.height),
            originalOrientation: input.originalOrientation,
            visionOrientation: input.visionOrientation,
            events: ["Prepared programmatic VisionKit input with scale \(String(format: "%.3f", input.scale))"]
        )

        let analyzer = ImageAnalyzer()
        let configuration = ImageAnalyzer.Configuration(.visualLookUp)
        let analysis: ImageAnalysis
        do {
            analysis = try await analyzer.analyze(input.sourceImage, configuration: configuration)
            diagnostics.events.append("ImageAnalyzer.analyze succeeded")
        } catch {
            throw StickerVisionFailure(stage: .performRequest, underlyingError: error)
        }

        let interaction = ImageAnalysisInteraction()
        interaction.preferredInteractionTypes = .imageSubject
        let analysisHost = VisionKitSubjectAnalysisHost(image: input.sourceImage, interaction: interaction)
        let attachedToWindow = analysisHost.attachToActiveWindow()
        defer {
            analysisHost.detach()
        }
        interaction.analysis = analysis
        interaction.setContentsRectNeedsUpdate()
        diagnostics.events.append("ImageAnalysis.hasVisualLookUp=\(analysis.hasResults(for: .visualLookUp))")
        diagnostics.events.append("VisionKitAnalysisHost.attachedToWindow=\(attachedToWindow)")

        let subjects = Array(await interaction.subjects)
            .sorted { lhs, rhs in
                if lhs.bounds.minY == rhs.bounds.minY {
                    return lhs.bounds.minX < rhs.bounds.minX
                }
                return lhs.bounds.minY < rhs.bounds.minY
            }

        guard !subjects.isEmpty else {
            throw StickerVisionFailure(stage: .readResults, detail: "ImageAnalysisInteraction.subjects was empty")
        }
        diagnostics.events.append("programmaticVisionKitSubjects=\(subjects.count)")

        var candidates: [StickerSubjectCandidate] = []
        var precomputedResults: [String: GeneratedStickerResult] = [:]

        for (index, subject) in subjects.enumerated() {
            let boundingBox = Self.normalizedVisionKitBoundingBox(
                subject.bounds,
                imageSize: CGSize(width: input.cgImage.width, height: input.cgImage.height)
            )
            let candidate = StickerSubjectCandidate(visionKitSubjectIndex: index, boundingBox: boundingBox)
            let subjectImage: UIImage
            do {
                subjectImage = try await subject.image
            } catch {
                throw StickerVisionFailure(stage: .generateMask, instanceIndex: index + 1, underlyingError: error)
            }

            candidates.append(candidate)
            precomputedResults[candidate.id] = try generatedStickerResult(from: subjectImage)
            diagnostics.instances.append(
                StickerVisionInstanceDiagnostic(
                    instanceIndex: index + 1,
                    maskPixelCount: 0,
                    boundingBox: boundingBox,
                    areaRatio: boundingBox.width * boundingBox.height,
                    decision: .accepted
                )
            )
        }

        if subjects.count > 1 {
            let allCandidate = StickerSubjectCandidate.selectAll(
                instanceIndexes: [],
                boundingBox: candidates.reduce(CGRect.null) { partialResult, candidate in
                    partialResult.union(candidate.boundingBox)
                }
            )
            let combinedImage = try await interaction.image(for: Set(subjects))
            precomputedResults[allCandidate.id] = try generatedStickerResult(from: combinedImage)
        }

        return StickerSubjectSelection(
            sourceImage: input.sourceImage,
            candidates: candidates,
            cgImage: input.cgImage,
            precomputedResults: precomputedResults,
            detectionMode: .visionKit,
            diagnostics: diagnostics
        )
    }

    @available(iOS 17.0, *)
    private func visionSubjectSelection(in image: UIImage) throws -> StickerSubjectSelection {
        let inputs: [StickerVisionInput]
        do {
            inputs = try Self.preparedVisionInputs(from: image)
        } catch {
            throw StickerVisionFailure(stage: .prepareImage, underlyingError: error)
        }

        var firstFailure: StickerVisionFailure?
        for input in inputs {
            do {
                var selection = try visionSubjectSelection(using: input)
                if let firstFailure {
                    selection.diagnostics.events.insert("Earlier full-resolution Vision attempt failed before fallback input: \(firstFailure.localizedDescription)", at: 0)
                }
                return selection
            } catch {
                let failure = error as? StickerVisionFailure ?? StickerVisionFailure(stage: .performRequest, underlyingError: error)
                firstFailure = firstFailure ?? failure
                Self.logVisionFailure(failure)
            }
        }

        throw firstFailure ?? StickerVisionFailure(stage: .performRequest, detail: "Vision returned no usable subjects for any prepared input")
    }

    @available(iOS 17.0, *)
    private func visionSubjectSelection(using input: StickerVisionInput) throws -> StickerSubjectSelection {
        var diagnostics = StickerVisionDiagnostics(
            mode: .vision,
            originalPixelSize: input.originalPixelSize,
            normalizedPixelSize: CGSize(width: input.cgImage.width, height: input.cgImage.height),
            originalOrientation: input.originalOrientation,
            visionOrientation: input.visionOrientation,
            events: ["Prepared Vision input with scale \(String(format: "%.3f", input.scale))"]
        )

        let request = VNGenerateForegroundInstanceMaskRequest()
        guard !type(of: request).supportedRevisions.isEmpty else {
            throw StickerVisionFailure(stage: .performRequest, detail: "VNGenerateForegroundInstanceMaskRequest has no supported revisions on this runtime")
        }

        let handler = VNImageRequestHandler(cgImage: input.cgImage, orientation: input.visionOrientation)
        do {
            try handler.perform([request])
            diagnostics.events.append("request.perform succeeded")
        } catch {
            throw StickerVisionFailure(stage: .performRequest, underlyingError: error)
        }

        guard let observation = request.results?.first as? VNInstanceMaskObservation else {
            throw StickerVisionFailure(stage: .readResults, detail: "VNGenerateForegroundInstanceMaskRequest returned no VNInstanceMaskObservation")
        }
        guard !observation.allInstances.isEmpty else {
            throw StickerVisionFailure(stage: .readResults, detail: "VNInstanceMaskObservation.allInstances was empty")
        }
        diagnostics.events.append("allInstances=\(Array(observation.allInstances))")

        var candidates: [StickerSubjectCandidate] = []
        var firstFailure: StickerVisionFailure?
        for instanceIndex in observation.allInstances {
            let maskBuffer: CVPixelBuffer
            do {
                maskBuffer = try observation.generateScaledMaskForImage(forInstances: IndexSet(integer: instanceIndex), from: handler)
            } catch {
                let failure = StickerVisionFailure(stage: .generateMask, instanceIndex: instanceIndex, underlyingError: error)
                diagnostics.instances.append(
                    StickerVisionInstanceDiagnostic(
                        instanceIndex: instanceIndex,
                        maskPixelCount: 0,
                        boundingBox: nil,
                        areaRatio: 0,
                        decision: .rejected(failure.localizedDescription)
                    )
                )
                firstFailure = firstFailure ?? failure
                continue
            }

            guard let stats = Self.visibleMaskStats(inMaskPixelBuffer: maskBuffer) else {
                diagnostics.instances.append(
                    StickerVisionInstanceDiagnostic(
                        instanceIndex: instanceIndex,
                        maskPixelCount: 0,
                        boundingBox: nil,
                        areaRatio: 0,
                        decision: .rejected("empty mask after generateScaledMaskForImage")
                    )
                )
                continue
            }

            let candidate = StickerSubjectCandidate(instanceIndex: instanceIndex, boundingBox: stats.boundingBox)
            candidates.append(candidate)
            diagnostics.instances.append(
                StickerVisionInstanceDiagnostic(
                    instanceIndex: instanceIndex,
                    maskPixelCount: stats.pixelCount,
                    boundingBox: stats.boundingBox,
                    areaRatio: stats.areaRatio,
                    decision: .accepted
                )
            )
        }
        diagnostics.events.append("acceptedCandidates=\(candidates.count)")

        guard !candidates.isEmpty else {
            Self.logDiagnostics(diagnostics)
            if let firstFailure {
                throw firstFailure
            }
            throw StickerVisionFailure(stage: .filterCandidate, detail: "all Vision instances were rejected; \(diagnostics.instances.map(\.summary).joined(separator: " | "))")
        }

        return StickerSubjectSelection(
            sourceImage: input.sourceImage,
            candidates: candidates,
            cgImage: input.cgImage,
            observation: observation,
            detectionMode: .vision,
            diagnostics: diagnostics
        )
    }

    @available(iOS 17.0, *)
    func transparentSticker(from selection: StickerSubjectSelection, candidate: StickerSubjectCandidate) throws -> GeneratedStickerResult {
        if let result = selection.precomputedResults[candidate.id] {
            return result
        }

        guard let observation = selection.observation else {
            throw StickerSubjectDetectionError.noForegroundFound
        }

        let handler = VNImageRequestHandler(cgImage: selection.cgImage, orientation: .up)
        let maskBuffer = try observation.generateScaledMaskForImage(forInstances: candidate.instanceIndexes, from: handler)
        let source = CIImage(cgImage: selection.cgImage)
        let mask = CIImage(cvPixelBuffer: maskBuffer)
        let uncroppedSticker = try renderer.transparentSticker(from: source, mask: mask)
        return try generatedStickerResult(from: croppedSticker(uncroppedSticker, to: candidate.boundingBox))
    }

    @available(iOS 17.0, *)
    func localSubjectSelection(in image: UIImage) throws -> StickerSubjectSelection {
        let input = try Self.preparedVisionInput(from: image, maxDimension: Self.visionMaxDimension)
        let normalized = input.sourceImage
        guard let source = CIImage(image: normalized) else {
            throw StickerSubjectDetectionError.invalidImage
        }

        let mask = try localForegroundMask(from: normalized)
        guard let boundingBox = Self.normalizedVisibleBoundingBox(in: mask),
              boundingBox.width > 0.04,
              boundingBox.height > 0.04,
              boundingBox.width < 0.985,
              boundingBox.height < 0.985,
              boundingBox.width * boundingBox.height < 0.92 else {
            throw StickerSubjectDetectionError.noForegroundFound
        }

        guard let maskImage = CIImage(image: mask) else {
            throw StickerMaskError.cannotCreateOutput
        }
        let uncroppedSticker = try renderer.transparentSticker(from: source, mask: maskImage)
        let result = try generatedStickerResult(
            from: croppedSticker(uncroppedSticker, to: boundingBox),
            isFallback: true,
            message: Self.userFacingMessage(for: StickerSubjectDetectionError.noForegroundFound, usedFallback: true)
        )
        let candidate = StickerSubjectCandidate(localSubjectBoundingBox: boundingBox)
        let diagnostics = StickerVisionDiagnostics(
            mode: .localFallback,
            originalPixelSize: input.originalPixelSize,
            normalizedPixelSize: CGSize(width: input.cgImage.width, height: input.cgImage.height),
            originalOrientation: input.originalOrientation,
            visionOrientation: input.visionOrientation,
            events: ["Local fallback produced one rough Subject candidate. This is not multi-object Vision detection."],
            instances: [
                StickerVisionInstanceDiagnostic(
                    instanceIndex: -1,
                    maskPixelCount: 0,
                    boundingBox: boundingBox,
                    areaRatio: boundingBox.width * boundingBox.height,
                    decision: .accepted
                )
            ]
        )

        return StickerSubjectSelection(
            sourceImage: normalized,
            candidates: [candidate],
            cgImage: input.cgImage,
            observation: nil,
            precomputedResults: [candidate.id: result],
            detectionMode: .localFallback,
            diagnostics: diagnostics
        )
    }

    func bestEffortSticker(from image: UIImage) throws -> GeneratedStickerResult {
        guard #available(iOS 17.0, *) else {
            return try fallbackSticker(from: image, error: LiveStickifyCameraError.foregroundMaskUnavailable)
        }

        do {
            return try transparentSticker(from: image)
        } catch {
            return try fallbackSticker(from: image, error: error)
        }
    }

    func fallbackSticker(from image: UIImage, error: Error? = nil) throws -> GeneratedStickerResult {
        try generatedStickerResult(
            from: simpleBackgroundCutoutSticker(from: image),
            isFallback: true,
            message: Self.userFacingMessage(for: error ?? LiveStickifyCameraError.foregroundMaskUnavailable, usedFallback: true)
        )
    }

    static func userFacingMessage(for error: Error, usedFallback: Bool) -> String {
        if usedFallback {
            return "已用本机简易抠图生成透明贴纸。复杂背景可能不完美，可以换一张主体更清晰的照片再试。"
        }

        if let liveError = error as? LiveStickifyCameraError {
            return liveError.localizedDescription
        }

        if let subjectError = error as? StickerSubjectDetectionError {
            return subjectError.localizedDescription
        }

        if let visionFailure = error as? StickerVisionFailure {
            let description = visionFailure.localizedDescription
            if description.localizedCaseInsensitiveContains("inference context")
                || description.localizedCaseInsensitiveContains("subjects was empty") {
                return StickerSubjectDetectionError.noForegroundFound.localizedDescription
            }
            return description
        }

        let description = (error as NSError).localizedDescription
        if description.localizedCaseInsensitiveContains("inference context") {
            return StickerSubjectDetectionError.noForegroundFound.localizedDescription
        }

        return "贴纸生成失败。请换一张主体更清晰、背景更简单的照片。"
    }

    @available(iOS 17.0, *)
    static func autoCaptureStatusMessage(for selection: StickerSubjectSelection) -> String {
        if selection.detectionMode == .localFallback {
            return "Auto 只找到一个粗略主体，复杂背景可能需要手动重拍"
        }

        let count = selection.candidates.count
        if count == 1 {
            return "Auto 找到 1 个可制作贴纸的主体，请点击收集"
        }
        return "Auto 找到 \(count) 个可制作贴纸的主体，请点击要收集的物体"
    }

    static func decodedPhotoImage(from data: Data) throws -> UIImage {
        if let source = CGImageSourceCreateWithData(data as CFData, nil) {
            let options: [CFString: Any] = [
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceDecodeRequest: kCGImageSourceDecodeToSDR
            ]
            if let cgImage = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary),
               !Self.isNearlyBlack(cgImage) {
                return UIImage(cgImage: cgImage, scale: 1, orientation: Self.imageOrientation(from: source))
            }
        }

        let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let ciOptions: [CIImageOption: Any] = [
            .applyOrientationProperty: true,
            .toneMapHDRtoSDR: true,
            .expandToHDR: false,
            .colorSpace: sRGB
        ]
        if let ciImage = CIImage(data: data, options: ciOptions) {
            let context = CIContext(options: [
                .workingColorSpace: sRGB,
                .outputColorSpace: sRGB
            ])
            let extent = ciImage.extent.integral
            if let cgImage = context.createCGImage(ciImage, from: extent, format: .RGBA8, colorSpace: sRGB),
               !Self.isNearlyBlack(cgImage) {
                return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
            }
        }

        guard let image = UIImage(data: data) else {
            throw StickerSubjectDetectionError.invalidImage
        }
        return image
    }

    private static func imageOrientation(from source: CGImageSource) -> UIImage.Orientation {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let rawOrientation = properties[kCGImagePropertyOrientation] as? UInt32,
              let cgOrientation = CGImagePropertyOrientation(rawValue: rawOrientation) else {
            return .up
        }
        return UIImage.Orientation(cgOrientation)
    }

    private static func isNearlyBlack(_ cgImage: CGImage) -> Bool {
        let width = 32
        let height = 32
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }

        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        var brightest: UInt8 = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            brightest = max(brightest, pixels[index], pixels[index + 1], pixels[index + 2])
            if brightest > 10 {
                return false
            }
        }
        return true
    }

    static func normalizedVisionKitBoundingBox(_ bounds: CGRect, imageSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return .zero
        }

        let standardizedBounds = bounds.standardized
        let looksNormalized = standardizedBounds.width <= 1
            && standardizedBounds.height <= 1
            && standardizedBounds.minX >= -1
            && standardizedBounds.minY >= -1
            && standardizedBounds.maxX <= 2
            && standardizedBounds.maxY <= 2

        let normalized: CGRect
        if looksNormalized {
            normalized = standardizedBounds
        } else {
            normalized = CGRect(
                x: standardizedBounds.minX / imageSize.width,
                y: standardizedBounds.minY / imageSize.height,
                width: standardizedBounds.width / imageSize.width,
                height: standardizedBounds.height / imageSize.height
            )
        }

        let clipped = normalized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !clipped.isNull, !clipped.isEmpty else {
            return .zero
        }
        return clipped.standardized
    }

    static func preparedVisionKitInputs(from image: UIImage) throws -> [StickerVisionInput] {
        try preparedVisionInputs(from: image)
    }

    static func preparedVisionInputs(from image: UIImage) throws -> [StickerVisionInput] {
        let fullResolution = try preparedVisionInput(from: image, maxDimension: .greatestFiniteMagnitude)
        let downscaled = try preparedVisionInput(from: image, maxDimension: visionMaxDimension)

        if fullResolution.cgImage.width == downscaled.cgImage.width,
           fullResolution.cgImage.height == downscaled.cgImage.height {
            return [fullResolution]
        }

        return [fullResolution, downscaled]
    }

    static func preparedVisionInput(from image: UIImage, maxDimension: CGFloat = visionMaxDimension) throws -> StickerVisionInput {
        guard maxDimension > 0,
              let cgImage = image.cgImage else {
            throw StickerSubjectDetectionError.invalidImage
        }

        let originalPixelSize = CGSize(width: cgImage.width, height: cgImage.height)
        let originalOrientation = image.imageOrientation
        let inputOrientation = CGImagePropertyOrientation(originalOrientation)
        let oriented = CIImage(cgImage: cgImage).oriented(inputOrientation)
        let orientedExtent = oriented.extent.integral
        guard orientedExtent.width > 0, orientedExtent.height > 0 else {
            throw StickerSubjectDetectionError.invalidImage
        }

        let translated = oriented.transformed(
            by: CGAffineTransform(translationX: -orientedExtent.minX, y: -orientedExtent.minY)
        )
        let longestSide = max(orientedExtent.width, orientedExtent.height)
        let scale = min(1, maxDimension / longestSide)
        let outputSize = CGSize(
            width: max(1, (orientedExtent.width * scale).rounded()),
            height: max(1, (orientedExtent.height * scale).rounded())
        )
        let scaled = translated.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let outputExtent = CGRect(origin: .zero, size: outputSize)

        guard let normalizedCGImage = visionContext.createCGImage(scaled, from: outputExtent) else {
            throw StickerMaskError.cannotCreateOutput
        }

        return StickerVisionInput(
            sourceImage: UIImage(cgImage: normalizedCGImage, scale: 1, orientation: .up),
            cgImage: normalizedCGImage,
            originalPixelSize: originalPixelSize,
            originalOrientation: originalOrientation,
            visionOrientation: .up,
            scale: scale
        )
    }

    private static func logVisionFailure(_ failure: StickerVisionFailure) {
        visionLogger.error("\(failure.localizedDescription, privacy: .public)")
    }

    private static func logDiagnostics(_ diagnostics: StickerVisionDiagnostics) {
        visionLogger.notice("\(diagnostics.summary, privacy: .public)")
    }

    private func simpleBackgroundCutoutSticker(from image: UIImage) throws -> UIImage {
        let normalized = image.normalizedForVision()
        let side = 512
        let canvasSize = CGSize(width: side, height: side)
        let contentRect = CGRect(x: 24, y: 24, width: side - 48, height: side - 48)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false

        let flattened = UIGraphicsImageRenderer(size: canvasSize, format: format).image { _ in
            let aspect = min(contentRect.width / max(normalized.size.width, 1), contentRect.height / max(normalized.size.height, 1))
            let drawSize = CGSize(width: normalized.size.width * aspect, height: normalized.size.height * aspect)
            let drawRect = CGRect(
                x: contentRect.midX - drawSize.width / 2,
                y: contentRect.midY - drawSize.height / 2,
                width: drawSize.width,
                height: drawSize.height
            )
            normalized.draw(in: drawRect)
        }

        guard let cgImage = flattened.cgImage else {
            throw StickerMaskError.cannotCreateOutput
        }

        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: &pixels,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw StickerMaskError.cannotCreateOutput
        }
        context.draw(cgImage, in: CGRect(origin: .zero, size: canvasSize))

        let background = estimatedBackgroundColor(from: pixels, width: side, height: side)
        for pixelIndex in stride(from: 0, to: pixels.count, by: 4) {
            guard pixels[pixelIndex + 3] > 0 else { continue }
            let distance = colorDistance(
                red: pixels[pixelIndex],
                green: pixels[pixelIndex + 1],
                blue: pixels[pixelIndex + 2],
                background: background
            )
            if distance < 54 {
                pixels[pixelIndex + 3] = 0
            } else if distance < 86 {
                let fade = CGFloat(distance - 54) / 32
                pixels[pixelIndex + 3] = UInt8(max(0, min(255, CGFloat(pixels[pixelIndex + 3]) * fade)))
            }
        }

        guard let cutoutContext = CGContext(
            data: &pixels,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ), let cutoutImage = cutoutContext.makeImage() else {
            throw StickerMaskError.cannotCreateOutput
        }

        return UIImage(cgImage: cutoutImage, scale: 1, orientation: .up)
    }

    private func generatedStickerResult(
        from originalImage: UIImage,
        isFallback: Bool = false,
        message: String? = nil
    ) throws -> GeneratedStickerResult {
        let sticker = try StickerStyleRenderer().styledSticker(from: originalImage, style: .whiteBorder)
        return GeneratedStickerResult(
            image: sticker,
            pngData: try renderer.pngData(from: sticker),
            originalImageData: try renderer.pngData(from: originalImage),
            isFallback: isFallback,
            message: message
        )
    }

    private func estimatedBackgroundColor(from pixels: [UInt8], width: Int, height: Int) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var count: CGFloat = 0
        let inset = 32

        for y in stride(from: inset, to: height - inset, by: 12) {
            for x in [inset, width - inset - 1] {
                addOpaquePixel(x: x, y: y, pixels: pixels, width: width, red: &red, green: &green, blue: &blue, count: &count)
            }
        }
        for x in stride(from: inset, to: width - inset, by: 12) {
            for y in [inset, height - inset - 1] {
                addOpaquePixel(x: x, y: y, pixels: pixels, width: width, red: &red, green: &green, blue: &blue, count: &count)
            }
        }

        guard count > 0 else {
            return (255, 255, 255)
        }
        return (red / count, green / count, blue / count)
    }

    private func addOpaquePixel(
        x: Int,
        y: Int,
        pixels: [UInt8],
        width: Int,
        red: inout CGFloat,
        green: inout CGFloat,
        blue: inout CGFloat,
        count: inout CGFloat
    ) {
        let index = (y * width + x) * 4
        guard pixels[index + 3] > 0 else { return }
        red += CGFloat(pixels[index])
        green += CGFloat(pixels[index + 1])
        blue += CGFloat(pixels[index + 2])
        count += 1
    }

    private func colorDistance(
        red: UInt8,
        green: UInt8,
        blue: UInt8,
        background: (red: CGFloat, green: CGFloat, blue: CGFloat)
    ) -> CGFloat {
        let redDelta = CGFloat(red) - background.red
        let greenDelta = CGFloat(green) - background.green
        let blueDelta = CGFloat(blue) - background.blue
        return sqrt(redDelta * redDelta + greenDelta * greenDelta + blueDelta * blueDelta)
    }

    private func croppedSticker(_ image: UIImage, to normalizedBox: CGRect) -> UIImage {
        guard let cgImage = image.cgImage else { return image }

        let imageRect = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        let objectRect = CGRect(
            x: normalizedBox.minX * imageRect.width,
            y: normalizedBox.minY * imageRect.height,
            width: normalizedBox.width * imageRect.width,
            height: normalizedBox.height * imageRect.height
        )
        let padding = max(max(objectRect.width, objectRect.height) * 0.12, 18)
        let cropRect = objectRect
            .insetBy(dx: -padding, dy: -padding)
            .intersection(imageRect)
            .integral

        guard cropRect.width > 1,
              cropRect.height > 1,
              let cropped = cgImage.cropping(to: cropRect) else {
            return image
        }

        return UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
    }

    private func localForegroundMask(from image: UIImage) throws -> UIImage {
        let normalized = image.normalizedForVision()
        let longestSide = max(normalized.size.width, normalized.size.height)
        guard longestSide > 0 else {
            throw StickerSubjectDetectionError.invalidImage
        }

        let renderScale = min(1, 768 / longestSide)
        let width = max(1, Int((normalized.size.width * renderScale).rounded()))
        let height = max(1, Int((normalized.size.height * renderScale).rounded()))
        let renderSize = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let flattened = UIGraphicsImageRenderer(size: renderSize, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: renderSize))
            normalized.draw(in: CGRect(origin: .zero, size: renderSize))
        }

        guard let cgImage = flattened.cgImage else {
            throw StickerMaskError.cannotCreateOutput
        }

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
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let background = estimatedBackgroundColor(from: pixels, width: width, height: height)
        var maskPixels = [UInt8](repeating: 0, count: width * height * 4)
        var foregroundPixels = 0

        for pixelIndex in stride(from: 0, to: pixels.count, by: 4) {
            let distance = colorDistance(
                red: pixels[pixelIndex],
                green: pixels[pixelIndex + 1],
                blue: pixels[pixelIndex + 2],
                background: background
            )

            let alpha: UInt8
            if distance < 42 {
                alpha = 0
            } else if distance < 82 {
                alpha = UInt8(max(0, min(255, ((distance - 42) / 40) * 255)))
            } else {
                alpha = 255
            }

            maskPixels[pixelIndex] = alpha
            maskPixels[pixelIndex + 1] = alpha
            maskPixels[pixelIndex + 2] = alpha
            maskPixels[pixelIndex + 3] = 255

            if alpha > 24 {
                foregroundPixels += 1
            }
        }

        guard foregroundPixels > max(24, (width * height) / 200) else {
            throw StickerSubjectDetectionError.noForegroundFound
        }

        guard let maskContext = CGContext(
            data: &maskPixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let maskCGImage = maskContext.makeImage() else {
            throw StickerMaskError.cannotCreateOutput
        }

        return UIImage(cgImage: maskCGImage, scale: 1, orientation: .up)
    }

    static func normalizedVisibleBoundingBox(in maskImage: UIImage) -> CGRect? {
        guard let cgImage = maskImage.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
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
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1

        for row in 0..<height {
            for x in 0..<width {
                let index = (row * width + x) * 4
                let alpha = pixels[index + 3]
                let visible = max(pixels[index], pixels[index + 1], pixels[index + 2])
                guard alpha > 0, visible > 8 else { continue }

                let topLeftY = height - 1 - row
                minX = min(minX, x)
                minY = min(minY, topLeftY)
                maxX = max(maxX, x)
                maxY = max(maxY, topLeftY)
            }
        }

        guard maxX >= minX, maxY >= minY else { return nil }

        return CGRect(
            x: CGFloat(minX) / CGFloat(width),
            y: CGFloat(minY) / CGFloat(height),
            width: CGFloat(maxX - minX + 1) / CGFloat(width),
            height: CGFloat(maxY - minY + 1) / CGFloat(height)
        )
    }

    static func normalizedVisibleBoundingBox(inMaskPixelBuffer pixelBuffer: CVPixelBuffer) -> CGRect? {
        visibleMaskStats(inMaskPixelBuffer: pixelBuffer)?.boundingBox
    }

    static func visibleMaskStats(inMaskPixelBuffer pixelBuffer: CVPixelBuffer) -> StickerMaskStats? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0,
              height > 0,
              let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        var pixelCount = 0

        func recordVisiblePixel(x: Int, y: Int) {
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
            pixelCount += 1
        }

        switch format {
        case kCVPixelFormatType_OneComponent32Float:
            for y in 0..<height {
                let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float32.self)
                for x in 0..<width where row[x] > 0.01 {
                    recordVisiblePixel(x: x, y: y)
                }
            }
        case kCVPixelFormatType_OneComponent8:
            for y in 0..<height {
                let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
                for x in 0..<width where row[x] > 8 {
                    recordVisiblePixel(x: x, y: y)
                }
            }
        default:
            for y in 0..<height {
                let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
                for x in 0..<width {
                    let index = x * 4
                    let alpha = row[index + 3]
                    let visible = max(row[index], row[index + 1], row[index + 2])
                    if alpha > 0, visible > 8 {
                        recordVisiblePixel(x: x, y: y)
                    }
                }
            }
        }

        guard maxX >= minX, maxY >= minY else { return nil }

        let boundingBox = CGRect(
            x: CGFloat(minX) / CGFloat(width),
            y: CGFloat(minY) / CGFloat(height),
            width: CGFloat(maxX - minX + 1) / CGFloat(width),
            height: CGFloat(maxY - minY + 1) / CGFloat(height)
        )
        return StickerMaskStats(
            pixelCount: pixelCount,
            boundingBox: boundingBox,
            areaRatio: CGFloat(pixelCount) / CGFloat(width * height)
        )
    }

    private static func image(from pixelBuffer: CVPixelBuffer) throws -> UIImage {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = maskContext.createCGImage(ciImage, from: ciImage.extent) else {
            throw StickerMaskError.cannotCreateOutput
        }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }
}

extension UIImage {
    func normalizedForVision() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

extension UIImage.Orientation {
    init(_ orientation: CGImagePropertyOrientation) {
        switch orientation {
        case .up:
            self = .up
        case .upMirrored:
            self = .upMirrored
        case .down:
            self = .down
        case .downMirrored:
            self = .downMirrored
        case .left:
            self = .left
        case .leftMirrored:
            self = .leftMirrored
        case .right:
            self = .right
        case .rightMirrored:
            self = .rightMirrored
        }
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up:
            self = .up
        case .upMirrored:
            self = .upMirrored
        case .down:
            self = .down
        case .downMirrored:
            self = .downMirrored
        case .left:
            self = .left
        case .leftMirrored:
            self = .leftMirrored
        case .right:
            self = .right
        case .rightMirrored:
            self = .rightMirrored
        @unknown default:
            self = .up
        }
    }
}

private extension CGRect {
    var debugSummary: String {
        "x=\(String(format: "%.4f", origin.x)),y=\(String(format: "%.4f", origin.y)),w=\(String(format: "%.4f", width)),h=\(String(format: "%.4f", height))"
    }
}
