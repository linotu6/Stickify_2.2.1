@preconcurrency import AVFoundation
import UIKit

final class LiveStickifyCameraController: NSObject, ObservableObject {
    enum PermissionState: Equatable {
        case checking
        case authorized
        case denied
        case unavailable(String)
    }

    enum CaptureState: Equatable {
        case idle
        case capturing
        case processing
        case finished
        case failed(String)
    }

    let session = AVCaptureSession()

    @Published private(set) var permissionState: PermissionState = .checking
    @Published private(set) var captureState: CaptureState = .idle
    @Published private(set) var stickerImage: UIImage?
    @Published private(set) var stickerPNGData: Data?
    @Published private(set) var stickerOriginalPNGData: Data?
    @Published private(set) var capturedPhotoData: Data?
    @Published private(set) var stickerResultMessage: String?
    @Published private(set) var cameraPosition: AVCaptureDevice.Position = .back

    private let sessionQueue = DispatchQueue(label: "com.sirius.Stickify.live-camera.session")
    private let processingQueue = DispatchQueue(label: "com.sirius.Stickify.live-camera.processing", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private let segmentationService = StickerSegmentationService()
    private var photoDelegate: LivePhotoCaptureDelegate?
    private var videoInput: AVCaptureDeviceInput?
    private var isConfigured = false

    deinit {
        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    @MainActor
    func requestPermissionAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionState = .authorized
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    self.permissionState = granted ? .authorized : .denied
                    if granted {
                        self.configureAndStart()
                    }
                }
            }
        case .denied, .restricted:
            permissionState = .denied
        @unknown default:
            permissionState = .denied
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    @MainActor
    func capture() {
        guard permissionState == .authorized else { return }
        captureState = .capturing

        // Camera capture pipeline:
        // AVCaptureSession owns the live preview; AVCapturePhotoOutput captures one still only
        // when the user taps Capture, avoiding expensive segmentation on every video frame.
        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .balanced

        let delegate = LivePhotoCaptureDelegate { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let capturedPhoto):
                    self.captureState = .processing
                    self.generateSticker(from: capturedPhoto)
                case .failure:
                    self.captureState = .failed(LiveStickifyCameraError.captureFailed.localizedDescription)
                }
                self.photoDelegate = nil
            }
        }
        photoDelegate = delegate
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }

    @MainActor
    func captureSubjectSelection(completion: @escaping @MainActor (Result<StickerSubjectSelection, Error>) -> Void) {
        guard permissionState == .authorized else { return }
        captureState = .capturing

        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .balanced

        let delegate = LivePhotoCaptureDelegate { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let capturedPhoto):
                    self.captureState = .processing
                    self.detectSubjects(from: capturedPhoto, completion: completion)
                case .failure(let error):
                    self.captureState = .failed(LiveStickifyCameraError.captureFailed.localizedDescription)
                    completion(.failure(error))
                }
                self.photoDelegate = nil
            }
        }
        photoDelegate = delegate
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }

    @MainActor
    func switchCamera() {
        guard permissionState == .authorized else { return }
        let targetPosition = cameraPosition == .back ? AVCaptureDevice.Position.front : .back

        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.switchCameraInput(to: targetPosition)
                Task { @MainActor in
                    self.cameraPosition = targetPosition
                }
            } catch {
                Task { @MainActor in
                    self.captureState = .failed(error.localizedDescription)
                }
            }
        }
    }

    @MainActor
    func clearStickerResult() {
        stickerImage = nil
        stickerPNGData = nil
        stickerOriginalPNGData = nil
        capturedPhotoData = nil
        stickerResultMessage = nil
        if captureState == .finished {
            captureState = .idle
        }
    }

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                if !self.isConfigured {
                    try self.configureSession()
                    self.isConfigured = true
                }
                if !self.session.isRunning {
                    self.session.startRunning()
                }
            } catch {
                Task { @MainActor in
                    self.permissionState = .unavailable(error.localizedDescription)
                }
            }
        }
    }

    private func configureSession() throws {
        session.beginConfiguration()
        session.sessionPreset = .photo
        defer { session.commitConfiguration() }

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw LiveStickifyCameraError.noCamera
        }

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            throw LiveStickifyCameraError.cannotConfigureCamera
        }
        session.addInput(input)
        videoInput = input

        guard session.canAddOutput(photoOutput) else {
            throw LiveStickifyCameraError.cannotConfigureCamera
        }
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .balanced
    }

    private func switchCameraInput(to position: AVCaptureDevice.Position) throws {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw LiveStickifyCameraError.noCamera
        }
        let newInput = try AVCaptureDeviceInput(device: camera)

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if let videoInput {
            session.removeInput(videoInput)
        }

        if session.canAddInput(newInput) {
            session.addInput(newInput)
            videoInput = newInput
        } else {
            if let videoInput, session.canAddInput(videoInput) {
                session.addInput(videoInput)
            }
            throw LiveStickifyCameraError.cannotConfigureCamera
        }
    }

    @MainActor
    private func generateSticker(from capturedPhoto: CapturedCameraPhoto) {
        processingQueue.async { [weak self] in
            guard let self else { return }
            do {
                guard #available(iOS 17.0, *) else {
                    throw LiveStickifyCameraError.foregroundMaskUnavailable
                }
                let result = try self.segmentationService.bestEffortSticker(from: capturedPhoto.image)
                Task { @MainActor in
                    self.stickerImage = result.image
                    self.capturedPhotoData = capturedPhoto.data
                    self.stickerPNGData = result.pngData
                    self.stickerOriginalPNGData = result.originalImageData
                    self.stickerResultMessage = result.message
                    self.captureState = .finished
                }
            } catch {
                Task { @MainActor in
                    self.captureState = .failed(StickerSegmentationService.userFacingMessage(for: error, usedFallback: false))
                }
            }
        }
    }

    @MainActor
    private func detectSubjects(
        from capturedPhoto: CapturedCameraPhoto,
        completion: @escaping @MainActor (Result<StickerSubjectSelection, Error>) -> Void
    ) {
        Task {
            do {
                guard #available(iOS 17.0, *) else {
                    throw LiveStickifyCameraError.foregroundMaskUnavailable
                }
                var selection = try await segmentationService.detectPhotoSubjectCandidates(in: capturedPhoto.image)
                selection.sourceOriginalPhotoData = capturedPhoto.data
                captureState = .idle
                completion(.success(selection))
            } catch {
                captureState = .failed(StickerSegmentationService.userFacingMessage(for: error, usedFallback: false))
                completion(.failure(error))
            }
        }
    }
}

struct CapturedCameraPhoto {
    var image: UIImage
    var data: Data
}

// AVFoundation camera objects are coordinated through private serial queues in this controller.
// UI-facing state changes are hopped back to MainActor before touching published properties.
extension LiveStickifyCameraController: @unchecked Sendable {}

private final class LivePhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Result<CapturedCameraPhoto, Error>) -> Void

    init(completion: @escaping (Result<CapturedCameraPhoto, Error>) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            completion(.failure(error))
            return
        }
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            completion(.failure(LiveStickifyCameraError.invalidCapture))
            return
        }
        completion(.success(CapturedCameraPhoto(image: image, data: data)))
    }
}

enum LiveStickifyCameraError: LocalizedError {
    case noCamera
    case cannotConfigureCamera
    case captureFailed
    case invalidCapture
    case foregroundMaskUnavailable
    case noForegroundFound

    var errorDescription: String? {
        switch self {
        case .noCamera:
            "当前设备没有可用相机。你仍然可以从相册选择照片制作贴纸。"
        case .cannotConfigureCamera:
            "Stickify 暂时无法启动相机预览。"
        case .captureFailed:
            "相机没有成功拍到照片。你可以从相册选择图片继续生成透明贴纸。"
        case .invalidCapture:
            "Stickify 无法读取这张照片。请换一张图片再试。"
        case .foregroundMaskUnavailable:
            "当前设备或系统版本暂不支持自动抠图。"
        case .noForegroundFound:
            "没有找到清晰主体。请换成单个物体、背景更简单的照片。"
        }
    }
}
