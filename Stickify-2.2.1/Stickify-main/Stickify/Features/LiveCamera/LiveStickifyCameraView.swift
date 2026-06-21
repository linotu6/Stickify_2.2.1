import SwiftUI

struct LiveStickifyCameraView: View {
    @StateObject private var camera = LiveStickifyCameraController()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            StickifyTheme.carbonBlack.ignoresSafeArea()

            switch camera.permissionState {
            case .checking:
                ProgressView("Checking Camera...")
                    .tint(.white)
                    .foregroundStyle(.white)
            case .authorized:
                cameraExperience
            case .denied:
                messageView(
                    title: "Camera access needed",
                    message: "Enable camera permission in Settings to make a live Stickify cut-out.",
                    icon: "camera.fill"
                )
            case .unavailable(let message):
                messageView(title: "Live camera unavailable", message: message, icon: "exclamationmark.triangle.fill")
            }
        }
        .task {
            camera.requestPermissionAndStart()
        }
        .onDisappear {
            camera.stop()
        }
        .sheet(isPresented: Binding(
            get: { camera.stickerImage != nil },
            set: { newValue in
                if !newValue {
                    camera.clearStickerResult()
                }
            }
        )) {
            if let image = camera.stickerImage {
                StickerResultPreview(image: image, pngByteCount: camera.stickerPNGData?.count)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var cameraExperience: some View {
        ZStack {
            CameraPreviewView(session: camera.session)
                .ignoresSafeArea()

            LinearGradient(colors: [.black.opacity(0.5), .clear, .black.opacity(0.72)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                statusPanel
                captureBar
            }
            .padding(.horizontal, 22)
            .padding(.top, 54)
            .padding(.bottom, 28)
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(StickifyTheme.carbonBlack)
                    .frame(width: 42, height: 42)
                    .background(.white, in: Circle())
            }
            .accessibilityLabel("Close live camera")

            Spacer()

            Text("Live Stickify Camera")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            Image(systemName: "wand.and.stars")
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(StickifyTheme.classicBlue)
                .frame(width: 42, height: 42)
                .background(.white, in: Circle())
        }
    }

    private var statusPanel: some View {
        VStack(spacing: 8) {
            Label(statusTitle, systemImage: statusIcon)
                .font(.system(size: 15, weight: .black))
            Text(statusMessage)
                .font(.system(size: 12, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.78))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.18), lineWidth: 1))
    }

    private var captureBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("On-device only")
                    .font(.system(size: 13, weight: .black))
                Text("AVFoundation + Vision")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.68))
            }
            .foregroundStyle(.white)

            Spacer()

            Button {
                camera.capture()
            } label: {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 86, height: 86)
                    Circle()
                        .fill(captureButtonColor)
                        .frame(width: 68, height: 68)
                    if camera.captureState == .capturing || camera.captureState == .processing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 24, weight: .black))
                            .foregroundStyle(.white)
                    }
                }
            }
            .disabled(camera.captureState == .capturing || camera.captureState == .processing)
            .accessibilityLabel("Capture sticker")
        }
        .padding(.top, 18)
    }

    private var captureButtonColor: Color {
        switch camera.captureState {
        case .failed:
            StickifyTheme.energeticRed
        default:
            StickifyTheme.classicBlue
        }
    }

    private var statusTitle: String {
        switch camera.captureState {
        case .idle:
            "Point at one object"
        case .capturing:
            "Capturing photo"
        case .processing:
            "Cutting foreground"
        case .finished:
            "Sticker ready"
        case .failed:
            "Try again"
        }
    }

    private var statusIcon: String {
        switch camera.captureState {
        case .idle:
            "viewfinder"
        case .capturing:
            "camera.fill"
        case .processing:
            "wand.and.stars"
        case .finished:
            "checkmark.seal.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private var statusMessage: String {
        switch camera.captureState {
        case .idle:
            "Segmentation runs only after Capture for a stable v1."
        case .capturing:
            "Freezing one frame from AVCapturePhotoOutput."
        case .processing:
            "Vision is generating a foreground mask locally."
        case .finished:
            "Transparent PNG generated in memory."
        case .failed(let message):
            message
        }
    }

    private func messageView(title: String, message: String, icon: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 42, weight: .black))
                .foregroundStyle(StickifyTheme.classicBlue)
            Text(title)
                .font(.system(size: 25, weight: .black, design: .rounded))
            Text(message)
                .font(.system(size: 15, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Close") { dismiss() }
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(StickifyTheme.classicBlue, in: Capsule())
        }
        .padding(28)
        .background(.white, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .padding(28)
    }
}

private struct StickerResultPreview: View {
    let image: UIImage
    let pngByteCount: Int?

    var body: some View {
        NavigationStack {
            ZStack {
                checkerboard
                    .ignoresSafeArea()

                VStack(spacing: 22) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 430)
                        .padding(24)
                        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 34, style: .continuous))
                        .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 14)

                    VStack(spacing: 7) {
                        Text("Transparent sticker ready")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                        Text(byteCountText)
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(24)
            }
            .navigationTitle("Sticker Preview")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var byteCountText: String {
        guard let pngByteCount else { return "PNG with alpha generated on-device" }
        return "PNG with alpha - \(pngByteCount) bytes"
    }

    private var checkerboard: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let square: CGFloat = 18
                for row in 0..<Int(size.height / square + 1) {
                    for col in 0..<Int(size.width / square + 1) {
                        let isLight = (row + col).isMultiple(of: 2)
                        context.fill(
                            Path(CGRect(x: CGFloat(col) * square, y: CGFloat(row) * square, width: square, height: square)),
                            with: .color(isLight ? .white : StickifyTheme.orderGrey)
                        )
                    }
                }
            }
        }
    }
}
