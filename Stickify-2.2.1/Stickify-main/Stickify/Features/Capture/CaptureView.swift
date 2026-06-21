import Photos
import PhotosUI
import SwiftUI

struct CaptureView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var demoState: StickifyDemoState
    @StateObject private var camera = LiveStickifyCameraController()
    @State private var photoSelection: PhotosPickerItem?
    @State private var showShelf = false
    @State private var showCleanup = false
    @State private var pendingCameraOriginalPhotoData: Data?
    @State private var isImportingPhoto = false
    @State private var statusMessage = Self.defaultStatusMessage
    @State private var lastSavedSticker: StickerItem?
    @State private var subjectSelection: StickerSubjectSelection?
    @State private var subjectSelectionSource: StickerSource = .photoLibrary
    @State private var isAutoCapturing = false
    @State private var captureContainerSize: CGSize = .zero
    @State private var cloudFrame: CGRect = .zero
    @State private var stickerFlight: StickerFlight?
    @State private var stickerFlightArrived = false
    @State private var cloudPulse = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                cameraSurface
                    .ignoresSafeArea()

                cameraChrome
                stickerFlightLayer
            }
            .coordinateSpace(name: Self.captureCoordinateSpaceName)
            .onAppear {
                captureContainerSize = proxy.size
            }
            .onChange(of: proxy.size) { _, size in
                captureContainerSize = size
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(StickifyTheme.carbonBlack)
        .ignoresSafeArea()
        .onPreferenceChange(CloudFramePreferenceKey.self) { frame in
            cloudFrame = frame
        }
        .task {
            camera.requestPermissionAndStart()
        }
        .onDisappear {
            camera.stop()
        }
        .onChange(of: camera.stickerPNGData) { _, pngData in
            guard let pngData else { return }
            saveGeneratedSticker(
                pngData: pngData,
                source: .camera,
                originalImageData: camera.stickerOriginalPNGData,
                cameraOriginalPhotoData: camera.capturedPhotoData,
                sourceBoundingBox: nil,
                status: camera.stickerResultMessage
            )
            camera.clearStickerResult()
        }
        .onChange(of: photoSelection) { _, item in
            importPhoto(item)
        }
        .onChange(of: camera.cameraPosition) { _, position in
            statusMessage = position == .front ? "已切换到前置相机" : "已切换到后置相机"
        }
        .sheet(isPresented: $showShelf) {
            ShelfSheet(demoState: $demoState)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $subjectSelection) { selection in
            SubjectSelectionSheet(selection: selection) { result, sourceBoundingBox in
                let isAutoCameraSelection = subjectSelectionSource == .camera
                saveGeneratedSticker(
                    pngData: result.pngData,
                    source: subjectSelectionSource,
                    originalImageData: result.originalImageData,
                    cameraOriginalPhotoData: isAutoCameraSelection ? selection.sourceOriginalPhotoData : nil,
                    sourceBoundingBox: isAutoCameraSelection ? sourceBoundingBox : nil,
                    status: result.message ?? (isAutoCameraSelection ? "Auto 已保存选中的主体贴纸" : "已保存选中的主体贴纸")
                )
                subjectSelection = nil
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog("是否将本次拍照原图保存到相册？", isPresented: $showCleanup, titleVisibility: .visible) {
            Button("保留缓存，保存原图到相册") {
                handleCameraOriginalCacheChoice(.keep, rememberChoice: false)
            }
            Button("删除缓存，只保留贴纸", role: .destructive) {
                handleCameraOriginalCacheChoice(.delete, rememberChoice: false)
            }
            Button("以后不再询问，默认保留本次缓存") {
                handleCameraOriginalCacheChoice(.keep, rememberChoice: true)
            }
            Button("以后不再询问，默认删除本次缓存", role: .destructive) {
                handleCameraOriginalCacheChoice(.delete, rememberChoice: true)
            }
        } message: {
            Text("保留会把这次拍摄的原始照片写入系统相册。删除只是不保存这张原图，已经生成的贴纸会保留。")
        }
    }

    private static let captureCoordinateSpaceName = "capture-screen"

    @ViewBuilder
    private var cameraSurface: some View {
        switch camera.permissionState {
        case .authorized:
            CameraPreviewView(session: camera.session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .blur(radius: camera.captureState == .processing ? 2.5 : 0)
                .overlay(Color.black.opacity(camera.captureState == .processing ? 0.45 : 0.12))
        case .checking:
            CameraFallbackSurface(
                title: "正在启动相机",
                message: "Stickify 会在本机生成透明贴纸",
                icon: "camera.metering.center.weighted"
            )
        case .denied:
            CameraFallbackSurface(
                title: "需要相机权限",
                message: "你仍然可以从相册选择照片制作贴纸",
                icon: "lock.fill"
            )
        case .unavailable(let message):
            CameraFallbackSurface(
                title: "相机暂不可用",
                message: message,
                icon: "video.slash.fill"
            )
        }
    }

    private var cameraChrome: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 22)
                .padding(.top, 56)

            Spacer()

            ZStack(alignment: .trailing) {
                floatingShelf
                    .padding(.trailing, 18)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .frame(height: 430)

            Spacer()

            VStack(spacing: 14) {
                statusPill
                captureRecoveryCard
                captureControls
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 132)
        }
        .overlay(alignment: .top) {
            if let sticker = lastSavedSticker {
                SavedStickerToast(sticker: sticker)
                    .padding(.top, 112)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: lastSavedSticker?.id)
    }

    @ViewBuilder
    private var stickerFlightLayer: some View {
        if let stickerFlight {
            FlyingStickerView(flight: stickerFlight, isArrived: stickerFlightArrived)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Stickify")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.42), radius: 10, x: 0, y: 6)
                Text("万物皆可贴纸")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.82))
            }

            Spacer()

            HStack(spacing: 10) {
                Button {
                    camera.switchCamera()
                    statusMessage = camera.cameraPosition == .back ? "正在切换到前置相机" : "正在切换到后置相机"
                } label: {
                    Image(systemName: "camera.rotate.fill")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(StickifyTheme.carbonBlack)
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.96), in: Circle())
                        .shadow(color: .black.opacity(0.2), radius: 14, x: 0, y: 8)
                }
                .buttonStyle(.plain)
                .disabled(camera.permissionState != .authorized)
                .accessibilityLabel("切换前后摄像头")

                Button {
                    showShelf = true
                } label: {
                    Label("\(demoState.shelf.count)", systemImage: "cloud.fill")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(StickifyTheme.classicBlue)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 11)
                        .background(.white.opacity(0.96), in: Capsule())
                        .shadow(color: .black.opacity(0.2), radius: 14, x: 0, y: 8)
                }
                .accessibilityLabel("打开临时收集云")
            }
        }
    }

    private var floatingShelf: some View {
        Button {
            showShelf = true
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: -12) {
                    ForEach(demoState.shelf.prefix(5)) { sticker in
                        StickerChip(sticker: sticker, size: 54)
                    }
                }

                Text("\(demoState.shelf.count)")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(StickifyTheme.classicBlue, in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.82), lineWidth: 1))
                    .offset(x: 6, y: -10)
            }
            .frame(width: 74)
            .padding(.vertical, 10)
            .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 8)
            .contentShape(Rectangle())
            .scaleEffect(cloudPulse ? 1.1 : 1)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: CloudFramePreferenceKey.self,
                        value: proxy.frame(in: .named(Self.captureCoordinateSpaceName))
                    )
                }
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("临时收集云，\(demoState.shelf.count) 个贴纸")
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            if isImportingPhoto || isAutoCapturing || camera.captureState == .capturing || camera.captureState == .processing {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.8)
            } else {
                Image(systemName: statusIcon)
                    .font(.system(size: 13, weight: .black))
            }

            Text(currentStatusMessage)
                .font(.system(size: 13, weight: .heavy))
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(maxWidth: 318)
        .background(.black.opacity(0.46), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.18), lineWidth: 1))
    }

    @ViewBuilder
    private var captureRecoveryCard: some View {
        if case .failed = camera.captureState {
            HStack(spacing: 10) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(StickifyTheme.classicBlue)

                VStack(alignment: .leading, spacing: 3) {
                    Text("换一张主体更清晰的照片")
                        .font(.system(size: 13, weight: .black))
                    Text("相册会先识别主体，再让你选择要保存的对象。")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(StickifyTheme.carbonBlack.opacity(0.64))
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .foregroundStyle(StickifyTheme.carbonBlack)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: 318)
            .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 14, x: 0, y: 8)
        }
    }

    private var captureControls: some View {
        HStack(alignment: .center) {
            PhotosPicker(selection: $photoSelection, matching: .images) {
                CameraToolButton(icon: "photo.on.rectangle.angled", title: "相册")
            }
            .disabled(isImportingPhoto)

            Spacer()

            Button {
                statusMessage = "正在拍摄并生成透明 PNG"
                camera.capture()
            } label: {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.96))
                        .frame(width: 92, height: 92)
                    Circle()
                        .fill(captureButtonColor)
                        .frame(width: 70, height: 70)
                    Image(systemName: "camera.fill")
                        .font(.system(size: 24, weight: .black))
                        .foregroundStyle(.white)
                }
                .shadow(color: .black.opacity(0.24), radius: 18, x: 0, y: 10)
            }
            .buttonStyle(.plain)
            .disabled(camera.permissionState != .authorized || camera.captureState == .capturing || camera.captureState == .processing || isImportingPhoto)
            .accessibilityLabel("拍摄并生成贴纸")

            Spacer()

            Button {
                startAutoCaptureScan()
            } label: {
                CameraToolButton(icon: "scope", title: "Auto")
            }
            .buttonStyle(.plain)
            .disabled(camera.permissionState != .authorized || camera.captureState == .capturing || camera.captureState == .processing || isImportingPhoto || isAutoCapturing)
            .accessibilityLabel("Auto 扫描当前画面中的主体")
        }
    }

    private var captureButtonColor: Color {
        switch camera.captureState {
        case .failed:
            StickifyTheme.energeticRed
        default:
            StickifyTheme.classicBlue
        }
    }

    private var statusIcon: String {
        switch camera.captureState {
        case .finished:
            "checkmark.seal.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        default:
            isAutoCapturing ? "scope" : (photoSelection == nil ? "viewfinder" : "photo.fill")
        }
    }

    private var currentStatusMessage: String {
        if isAutoCapturing {
            return "Auto 正在定格当前画面并识别可收集主体"
        }
        if isImportingPhoto {
            return "正在识别照片里的主体"
        }
        switch camera.permissionState {
        case .checking:
            return "正在检查相机，也可以从相册选择图片"
        case .denied, .unavailable:
            if statusMessage != Self.defaultStatusMessage {
                return statusMessage
            }
            return "相机不可用，请从相册选择图片识别主体"
        case .authorized:
            break
        }
        switch camera.captureState {
        case .capturing:
            return isAutoCapturing ? "Auto 正在定格当前画面" : "正在定格当前画面"
        case .processing:
            return isAutoCapturing ? "Auto 正在本机识别可收集主体" : "Vision 正在本机抠出前景"
        case .failed(let message):
            return message
        default:
            return statusMessage
        }
    }

    private static let defaultStatusMessage = "对准物体，点击快门制作贴纸，或点 Auto 选择多个主体"

    private func importPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        isImportingPhoto = true
        statusMessage = "正在读取相册图片"

        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = try? StickerSegmentationService.decodedPhotoImage(from: data) else {
                    throw LiveStickifyCameraError.invalidCapture
                }

                guard #available(iOS 17.0, *) else {
                    throw StickerSubjectDetectionError.foregroundMaskUnavailable
                }

                let selection = try await StickerSegmentationService().detectPhotoSubjectCandidates(in: image)

                await MainActor.run {
                    subjectSelectionSource = .photoLibrary
                    subjectSelection = selection
                    switch selection.detectionMode {
                    case .visionKit:
                        statusMessage = selection.candidates.count == 1 ? "找到 1 个可制作贴纸的主体" : "找到 \(selection.candidates.count) 个可制作贴纸的主体"
                    case .vision:
                        statusMessage = selection.candidates.count == 1 ? "找到 1 个可制作贴纸的主体" : "找到 \(selection.candidates.count) 个可制作贴纸的主体"
                    case .localFallback:
                        statusMessage = "已显示一个本机粗略主体，可换一张背景更简单的照片"
                    }
                    isImportingPhoto = false
                    photoSelection = nil
                }
            } catch {
                await MainActor.run {
                    statusMessage = StickerSegmentationService.userFacingMessage(for: error, usedFallback: false)
                    isImportingPhoto = false
                    photoSelection = nil
                }
            }
        }
    }

    private func startAutoCaptureScan() {
        guard camera.permissionState == .authorized else { return }
        isAutoCapturing = true
        statusMessage = "Auto 正在定格当前画面"

        camera.captureSubjectSelection { result in
            isAutoCapturing = false
            switch result {
            case .success(let selection):
                subjectSelectionSource = .camera
                subjectSelection = selection
                statusMessage = StickerSegmentationService.autoCaptureStatusMessage(for: selection)
            case .failure(let error):
                statusMessage = StickerSegmentationService.userFacingMessage(for: error, usedFallback: false)
            }
        }
    }

    private func saveGeneratedSticker(
        pngData: Data,
        source: StickerSource,
        originalImageData: Data? = nil,
        cameraOriginalPhotoData: Data? = nil,
        sourceBoundingBox: CGRect? = nil,
        status: String? = nil
    ) {
        let sticker = demoState.addGeneratedSticker(
            imageData: pngData,
            source: source,
            originalImageData: originalImageData
        )
        lastSavedSticker = sticker
        statusMessage = status ?? "已吸入临时收集云，也存入灵感库"
        handleCameraOriginalPhotoData(cameraOriginalPhotoData, source: source)
        startStickerFlight(imageData: sticker.imageData ?? pngData, source: source, subjectBoundingBox: sourceBoundingBox)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            if lastSavedSticker?.id == sticker.id {
                lastSavedSticker = nil
            }
        }
    }

    private func startStickerFlight(imageData: Data, source: StickerSource, subjectBoundingBox: CGRect?) {
        guard source == .camera else { return }

        if reduceMotion {
            pulseCloud()
            return
        }

        let captureFrame = StickerFlightPath.defaultCaptureFrame(in: captureContainerSize)
        guard captureFrame != .zero else { return }
        let targetFrame = cloudFrame == .zero ? fallbackCloudFrame(in: captureContainerSize) : cloudFrame
        let path = StickerFlightPath(
            captureFrame: captureFrame,
            targetFrame: targetFrame,
            subjectBoundingBox: subjectBoundingBox
        )
        let flight = StickerFlight(imageData: imageData, start: path.start, target: path.target)

        stickerFlight = flight
        stickerFlightArrived = false

        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.72, dampingFraction: 0.78, blendDuration: 0.08)) {
                stickerFlightArrived = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.86) {
            if stickerFlight?.id == flight.id {
                stickerFlight = nil
                stickerFlightArrived = false
                pulseCloud()
            }
        }
    }

    private func fallbackCloudFrame(in containerSize: CGSize) -> CGRect {
        CGRect(
            x: max(containerSize.width - 98, 0),
            y: max((containerSize.height - 90) / 2, 0),
            width: 74,
            height: 90
        )
    }

    private func pulseCloud() {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.58)) {
            cloudPulse = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                cloudPulse = false
            }
        }
    }

    private func handleCameraOriginalPhotoData(_ data: Data?, source: StickerSource) {
        guard source == .camera, let data else { return }

        if demoState.cameraOriginalCachePreference.shouldAsk {
            pendingCameraOriginalPhotoData = data
            showCleanup = true
        } else {
            var coordinator = CameraOriginalCacheCoordinator(
                preference: demoState.cameraOriginalCachePreference,
                saveOriginalToPhotos: saveCameraOriginalPhotoToPhotos
            )
            demoState.cameraOriginalCachePreference = coordinator.handleOriginalPhotoData(
                data,
                action: nil,
                rememberChoice: false
            )
        }
    }

    private func handleCameraOriginalCacheChoice(_ action: CameraOriginalCacheAction, rememberChoice: Bool) {
        var coordinator = CameraOriginalCacheCoordinator(
            preference: demoState.cameraOriginalCachePreference,
            saveOriginalToPhotos: saveCameraOriginalPhotoToPhotos
        )
        demoState.cameraOriginalCachePreference = coordinator.handleOriginalPhotoData(
            pendingCameraOriginalPhotoData,
            action: action,
            rememberChoice: rememberChoice
        )
        pendingCameraOriginalPhotoData = nil
    }

    private func saveCameraOriginalPhotoToPhotos(_ data: Data) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    statusMessage = "没有相册写入权限，贴纸已保留"
                }
                return
            }

            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    statusMessage = success ? "贴纸已保留，原图已保存到相册" : (error?.localizedDescription ?? "原图保存到相册失败，贴纸已保留")
                }
            }
        }
    }

}

private struct StickerFlight: Identifiable, Equatable {
    var id = UUID()
    var imageData: Data
    var start: CGPoint
    var target: CGPoint
}

private struct FlyingStickerView: View {
    var flight: StickerFlight
    var isArrived: Bool

    var body: some View {
        Group {
            if let image = UIImage(data: flight.imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "seal.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 92, height: 92)
        .padding(8)
        .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(isArrived ? 0.08 : 0.26), radius: isArrived ? 8 : 20, x: 0, y: isArrived ? 4 : 12)
        .scaleEffect(isArrived ? 0.36 : 1.14)
        .rotationEffect(.degrees(isArrived ? 10 : -5))
        .opacity(isArrived ? 0.08 : 1)
        .position(isArrived ? flight.target : flight.start)
    }
}

private struct CloudFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

private struct CameraFallbackSurface: View {
    var title: String
    var message: String
    var icon: String

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x101820), Color(hex: 0x293844)], startPoint: .top, endPoint: .bottom)

            VStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 38, weight: .black))
                Text(title)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                Text(message)
                    .font(.system(size: 14, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(maxWidth: 220)
            }
            .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CameraToolButton: View {
    var icon: String
    var title: String

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .black))
            Text(title)
                .font(.system(size: 12, weight: .black))
        }
        .foregroundStyle(StickifyTheme.carbonBlack)
        .frame(width: 72, height: 72)
        .background(.white.opacity(0.92), in: Circle())
        .shadow(color: .black.opacity(0.2), radius: 14, x: 0, y: 8)
    }
}

private struct SavedStickerToast: View {
    var sticker: StickerItem

    var body: some View {
        HStack(spacing: 10) {
            StickerChip(sticker: sticker, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("贴纸已保存")
                    .font(.system(size: 14, weight: .black))
                Text("已进入临时云和灵感库")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(.white.opacity(0.96), in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
    }
}

@available(iOS 17.0, *)
private struct SubjectSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    var selection: StickerSubjectSelection
    var onSave: (GeneratedStickerResult, CGRect?) -> Void
    @State private var selectedCandidateID: StickerSubjectCandidate.ID?
    @State private var previewResult: GeneratedStickerResult?
    @State private var isRendering = false
    @State private var errorMessage: String?

    private var candidates: [StickerSubjectCandidate] {
        if let allInstancesCandidate = selection.allInstancesCandidate {
            return selection.candidates + [allInstancesCandidate]
        }
        return selection.candidates
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                photoStage
                previewPanel
                candidateStrip
                saveButton
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
            .navigationTitle("选择主体")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .task {
                if selectedCandidateID == nil, let first = selection.candidates.first {
                    render(first)
                }
            }
        }
    }

    private var photoStage: some View {
        GeometryReader { proxy in
            let imageRect = aspectFitRect(imageSize: selection.sourceSize, in: proxy.size)

            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.06)

                Image(uiImage: selection.sourceImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: proxy.size.width, height: proxy.size.height)

                ForEach(candidates) { candidate in
                    CandidateOverlayButton(
                        candidate: candidate,
                        rect: candidateRect(candidate.boundingBox, in: imageRect),
                        isSelected: selectedCandidateID == candidate.id,
                        action: {
                            render(candidate)
                        }
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .frame(height: 330)
    }

    private var previewPanel: some View {
        HStack(spacing: 14) {
            ZStack {
                StickerCheckerboard()
                if let previewResult {
                    Image(uiImage: previewResult.image)
                        .resizable()
                        .scaledToFit()
                        .padding(10)
                } else if isRendering {
                    ProgressView()
                } else {
                    Image(systemName: "lasso")
                        .font(.system(size: 24, weight: .black))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 104, height: 104)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.black.opacity(0.08), lineWidth: 1))

            VStack(alignment: .leading, spacing: 6) {
                Text(selectedTitle)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(StickifyTheme.carbonBlack)
                Text(errorMessage ?? "预览只包含当前选中的主体，透明背景会保存在 PNG 里。")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(errorMessage == nil ? .secondary : StickifyTheme.energeticRed)
                    .lineLimit(3)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.black.opacity(0.08), lineWidth: 1))
    }

    private var candidateStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(candidates) { candidate in
                    Button {
                        render(candidate)
                    } label: {
                        Label(candidate.title, systemImage: candidate.isSelectAll ? "square.stack.3d.up.fill" : "scope")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(selectedCandidateID == candidate.id ? .white : StickifyTheme.carbonBlack)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 10)
                            .background(selectedCandidateID == candidate.id ? StickifyTheme.classicBlue : Color.white, in: Capsule())
                            .overlay(Capsule().stroke(.black.opacity(0.08), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var saveButton: some View {
        Button {
            guard let previewResult else { return }
            let selectedBoundingBox = selectedCandidateID.flatMap { id in
                candidates.first { $0.id == id }?.boundingBox
            }
            onSave(previewResult, selectedBoundingBox)
            dismiss()
        } label: {
            HStack {
                Image(systemName: "tray.and.arrow.down.fill")
                Text("保存选中主体")
            }
            .font(.system(size: 16, weight: .black))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(previewResult == nil ? Color.gray.opacity(0.42) : StickifyTheme.classicBlue, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(previewResult == nil || isRendering)
    }

    private var selectedTitle: String {
        guard let selectedCandidateID,
              let candidate = candidates.first(where: { $0.id == selectedCandidateID }) else {
            return "选择一个主体"
        }
        return candidate.isSelectAll ? "全部主体" : candidate.title
    }

    private func render(_ candidate: StickerSubjectCandidate) {
        selectedCandidateID = candidate.id
        previewResult = nil
        errorMessage = nil
        isRendering = true

        Task { @MainActor in
            do {
                let result = try StickerSegmentationService().transparentSticker(from: selection, candidate: candidate)
                previewResult = result
                isRendering = false
            } catch {
                errorMessage = StickerSegmentationService.userFacingMessage(for: error, usedFallback: false)
                isRendering = false
            }
        }
    }

    private func candidateRect(_ boundingBox: CGRect, in imageRect: CGRect) -> CGRect {
        CGRect(
            x: imageRect.minX + boundingBox.minX * imageRect.width,
            y: imageRect.minY + boundingBox.minY * imageRect.height,
            width: boundingBox.width * imageRect.width,
            height: boundingBox.height * imageRect.height
        )
    }

    private func aspectFitRect(imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }

        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let fittedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (containerSize.width - fittedSize.width) / 2,
            y: (containerSize.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }
}

private struct CandidateOverlayButton: View {
    var candidate: StickerSubjectCandidate
    var rect: CGRect
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? StickifyTheme.classicBlue : .white, lineWidth: isSelected ? 4 : 3)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill((isSelected ? StickifyTheme.classicBlue : Color.black).opacity(isSelected ? 0.16 : 0.08))
                    )

                Text(candidate.overlayLabel)
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(isSelected ? .white : StickifyTheme.carbonBlack)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(isSelected ? StickifyTheme.classicBlue : .white.opacity(0.92), in: Capsule())
                    .padding(7)
            }
            .frame(width: max(rect.width, 48), height: max(rect.height, 48))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .position(x: rect.midX, y: rect.midY)
        .accessibilityLabel(candidate.isSelectAll ? "Select All" : candidate.title)
    }
}

private struct StickerCheckerboard: View {
    var body: some View {
        Canvas { context, size in
            let square: CGFloat = 12
            let rows = Int(ceil(size.height / square))
            let columns = Int(ceil(size.width / square))

            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    let rect = CGRect(
                        x: CGFloat(column) * square,
                        y: CGFloat(row) * square,
                        width: square,
                        height: square
                    )
                    context.fill(Path(rect), with: .color(Color.black.opacity(0.06)))
                }
            }
        }
        .background(Color.white)
    }
}

private struct ShelfSheet: View {
    @Binding var demoState: StickifyDemoState
    @State private var selectedCollectionIndex = 0
    @State private var isSelecting = false
    @State private var selectedStickerIds: Set<UUID> = []
    @State private var showDeleteConfirmation = false
    @State private var showNewLibraryPrompt = false
    @State private var newLibraryName = ""
    @State private var previewSticker: StickerItem?

    private var stickers: [StickerItem] {
        switch selectedCollection {
        case .shelf:
            return demoState.shelf
        case .library(let index):
            guard demoState.libraries.indices.contains(index) else { return [] }
            return demoState.libraries[index].stickers
        case .addLibrary:
            return []
        }
    }

    private var selectedCollection: ShelfCollection {
        if selectedCollectionIndex <= 0 {
            return .shelf
        }

        let libraryIndex = selectedCollectionIndex - 1
        if demoState.libraries.indices.contains(libraryIndex) {
            return .library(libraryIndex)
        }

        return .addLibrary
    }

    private var collectionTitle: String {
        switch selectedCollection {
        case .shelf:
            return "临时收集云"
        case .library(let index):
            return demoState.libraries[index].name
        case .addLibrary:
            return "添加云库"
        }
    }

    private var maxCollectionIndex: Int {
        demoState.libraries.count + 1
    }

    private var canGoPrevious: Bool {
        selectedCollectionIndex > 0
    }

    private var canGoNext: Bool {
        selectedCollectionIndex < maxCollectionIndex
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    if selectedCollection == .addLibrary {
                        addLibraryPlaceholder
                            .padding(22)
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 20) {
                            ForEach(stickers) { sticker in
                                Button {
                                    if isSelecting {
                                        toggle(sticker)
                                    } else {
                                        previewSticker = sticker
                                    }
                                } label: {
                                    VStack(spacing: 10) {
                                        ZStack {
                                            StickerChip(sticker: sticker, size: 88)
                                                .modifier(ShelfSelectionJiggle(isActive: isSelecting))

                                            if selectedStickerIds.contains(sticker.id) {
                                                RoundedRectangle(cornerRadius: 28, style: .continuous)
                                                    .stroke(Color.green, lineWidth: 4)
                                                    .frame(width: 96, height: 96)
                                                    .transition(.scale(scale: 0.86).combined(with: .opacity))
                                            }
                                        }
                                        .frame(width: 104, height: 104)

                                        Text(sticker.fallbackName)
                                            .font(.system(size: 12, weight: .heavy))
                                            .foregroundStyle(StickifyTheme.carbonBlack)
                                            .lineLimit(1)
                                    }
                                }
                                .buttonStyle(.plain)
                                .simultaneousGesture(LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                                    isSelecting = true
                                    selectedStickerIds.insert(sticker.id)
                                })
                            }
                        }
                        .padding(22)
                    }
                }
                .gesture(collectionSwipeGesture)
                .blur(radius: previewSticker == nil ? 0 : 18)
                .allowsHitTesting(previewSticker == nil)

                if let previewSticker {
                    ShelfStickerPreview(sticker: previewSticker) {
                        self.previewSticker = nil
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .navigationTitle(collectionTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 10) {
                        collectionArrow(systemName: "chevron.left", isEnabled: canGoPrevious) {
                            goPreviousCollection()
                        }

                        if isSelecting {
                            Text("选择模式")
                                .font(.system(size: 14, weight: .black))
                                .foregroundStyle(StickifyTheme.classicBlue)
                        }
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text(collectionTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(StickifyTheme.classicBlue)
                        .lineLimit(1)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 10) {
                        if isSelecting {
                            Button("取消") {
                                exitSelectionMode()
                            }

                            Button(role: .destructive) {
                                showDeleteConfirmation = true
                            } label: {
                                Image(systemName: "trash.fill")
                            }
                            .disabled(selectedStickerIds.isEmpty)
                        }

                        collectionArrow(systemName: "chevron.right", isEnabled: canGoNext) {
                            goNextCollection()
                        }
                    }
                }
            }
            .alert("创建新云库", isPresented: $showNewLibraryPrompt) {
                TextField("云库名称", text: $newLibraryName)
                Button("取消", role: .cancel) {
                    newLibraryName = ""
                }
                Button("确认") {
                    createLibrary()
                }
            } message: {
                Text("为新的贴纸云库命名。")
            }
            .alert("删除已选中贴纸？", isPresented: $showDeleteConfirmation) {
                Button("取消", role: .cancel) { }
                Button("删除", role: .destructive) {
                    deleteSelectedStickers()
                }
            } message: {
                Text("将从临时收集云和灵感库中删除 \(selectedStickerIds.count) 个贴纸。")
            }
            .animation(.spring(response: 0.26, dampingFraction: 0.82), value: selectedCollectionIndex)
            .animation(.spring(response: 0.26, dampingFraction: 0.82), value: isSelecting)
            .animation(.spring(response: 0.26, dampingFraction: 0.82), value: selectedStickerIds)
            .animation(.spring(response: 0.26, dampingFraction: 0.82), value: previewSticker?.id)
        }
    }

    private var addLibraryPlaceholder: some View {
        VStack(spacing: 14) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 42, weight: .black))
                .foregroundStyle(StickifyTheme.classicBlue)

            Text("添加云库")
                .font(.system(size: 22, weight: .black, design: .rounded))

            Text("点击右侧箭头或此区域创建新的贴纸云库。")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 220)

            Button {
                promptCreateLibrary()
            } label: {
                Label("命名并创建", systemImage: "cloud.fill")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(StickifyTheme.classicBlue, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 58)
    }

    private var collectionSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 28)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < -36 {
                    goNextCollection()
                } else if value.translation.width > 36 {
                    goPreviousCollection()
                }
            }
    }

    private func collectionArrow(systemName: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(isEnabled ? StickifyTheme.classicBlue : StickifyTheme.skyBlue.opacity(0.42))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func goPreviousCollection() {
        guard canGoPrevious else { return }
        selectedCollectionIndex -= 1
        exitSelectionMode()
    }

    private func goNextCollection() {
        guard canGoNext else { return }
        selectedCollectionIndex += 1
        exitSelectionMode()
        if selectedCollection == .addLibrary {
            promptCreateLibrary()
        }
    }

    private func promptCreateLibrary() {
        newLibraryName = ""
        showNewLibraryPrompt = true
    }

    private func createLibrary() {
        let createdLibrary = demoState.addCloud(named: newLibraryName)
        if let createdLibrary,
           let index = demoState.libraries.firstIndex(where: { $0.id == createdLibrary.id }) {
            selectedCollectionIndex = index + 1
        }
        newLibraryName = ""
    }

    private func toggle(_ sticker: StickerItem) {
        if selectedStickerIds.contains(sticker.id) {
            selectedStickerIds.remove(sticker.id)
        } else {
            selectedStickerIds.insert(sticker.id)
        }
    }

    private func exitSelectionMode() {
        isSelecting = false
        selectedStickerIds.removeAll()
    }

    private func deleteSelectedStickers() {
        selectedStickerIds.forEach { id in
            demoState.deleteSticker(id: id)
        }
        exitSelectionMode()
    }
}

private enum ShelfCollection: Equatable {
    case shelf
    case library(Int)
    case addLibrary
}

private struct ShelfStickerPreview: View {
    var sticker: StickerItem
    var onDismiss: () -> Void
    @State private var steadyScale: CGFloat = 1
    @State private var gestureScale: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()

            previewContent
                .scaleEffect(steadyScale * gestureScale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(26)
                .gesture(MagnificationGesture()
                    .onChanged { value in
                        gestureScale = value
                    }
                    .onEnded { value in
                        steadyScale = min(max(steadyScale * value, 0.5), 5)
                        gestureScale = 1
                    }
                )

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(StickifyTheme.carbonBlack)
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.94), in: Circle())
                    .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
            .padding(.trailing, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .accessibilityLabel("关闭原始预览")
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        if let image = sticker.generatedPreviewImage {
            OriginalSizeImage(image: image)
        } else {
            VStack(spacing: 12) {
                StickerChip(sticker: sticker, size: 210)
                Text(sticker.fallbackName)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.34), in: Capsule())
            }
        }
    }
}

private struct OriginalSizeImage: View {
    var image: UIImage

    var body: some View {
        GeometryReader { proxy in
            let fittedSize = Self.fittedSize(imageSize: image.size, containerSize: proxy.size)

            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: fittedSize.width, height: fittedSize.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private static func fittedSize(imageSize: CGSize, containerSize: CGSize) -> CGSize {
        guard imageSize.width > 0,
              imageSize.height > 0,
              containerSize.width > 0,
              containerSize.height > 0 else {
            return CGSize(width: 240, height: 240)
        }

        let maxWidth = containerSize.width - 52
        let maxHeight = containerSize.height - 52
        let scale = min(1, maxWidth / imageSize.width, maxHeight / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }
}

private extension StickerItem {
    var generatedPreviewImage: UIImage? {
        guard let imageData else { return nil }
        return UIImage(data: imageData)
    }
}

private struct ShelfSelectionJiggle: ViewModifier {
    var isActive: Bool
    @State private var isJiggling = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(isActive ? (isJiggling ? 2.2 : -2.2) : 0))
            .offset(x: isActive ? (isJiggling ? 1.2 : -1.2) : 0)
            .animation(
                isActive ? .easeInOut(duration: 0.16).repeatForever(autoreverses: true) : .default,
                value: isJiggling
            )
            .onChange(of: isActive) { _, active in
                isJiggling = active
            }
            .onAppear {
                isJiggling = isActive
            }
    }
}

