import PhotosUI
import SwiftUI

struct PlaygroundView: View {
    @Binding var demoState: StickifyDemoState
    @State private var selectedPlay: PlaygroundPlayKind?
    @State private var currentMode: PlaygroundMode = .stack
    @State private var selectedLibraryId: UUID?
    @State private var showLibraryPicker = false
    @State private var showDraftBox = false
    @State private var showSolidifyConfirmation = false
    @State private var showClearConfirmation = false
    @State private var showCropExitConfirmation = false
    @State private var isCropMode = false
    @State private var cropSide: CropSide = .right
    @State private var ratio: CanvasRatio = .square
    @State private var isToolLibraryExpanded = false
    @State private var showsDotGrid = false
    @State private var symmetryEnabled = false
    @State private var snapEnabled = false
    @State private var spacingJitter: Double = 24
    @State private var sizeJitter: Double = 18
    @State private var rotationJitter: Double = 24
    @State private var rotationDirection: RotationDirection = .mixed
    @State private var brushTool: BrushTool = .sticker
    @State private var brushWidth: Double = 8
    @State private var brushColor = StickifyTheme.energeticRed
    @State private var backdropSelection: PhotosPickerItem?
    @State private var backdropImageData: Data?
    @State private var drafts: [PlaygroundDraft] = []
    @State private var status = "选择一个玩法开始创作"

    private var selectedLibrary: StickerLibrary? {
        selectedLibraryId.flatMap { id in demoState.libraries.first { $0.id == id } } ?? demoState.libraries.first
    }

    private var selectedLibraryStickers: [StickerItem] {
        guard let selectedLibrary else { return demoState.shelf }
        return selectedLibrary.stickers.sorted {
            demoState.displayName(for: $0, in: selectedLibrary.id)
                .localizedStandardCompare(demoState.displayName(for: $1, in: selectedLibrary.id)) == .orderedAscending
        }
    }

    private var displayedTrayStickers: [StickerItem] {
        Array(selectedLibraryStickers.prefix(16))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            StickifyTheme.orderGrey.ignoresSafeArea()

            if let selectedPlay {
                workspace(for: selectedPlay)
            } else {
                home
            }
        }
        .foregroundStyle(StickifyTheme.carbonBlack)
        .onAppear {
            selectedLibraryId = selectedLibraryId ?? demoState.libraries.first?.id
        }
        .onChange(of: backdropSelection) { _, item in
            loadBackdropPhoto(item)
        }
        .sheet(isPresented: $showLibraryPicker) {
            libraryPicker
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showDraftBox) {
            draftBox
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .alert("清空编辑区？", isPresented: $showClearConfirmation) {
            Button("取消", role: .cancel) { }
            Button("清空", role: .destructive) {
                saveDraft(kind: selectedPlay, isSaved: false)
                demoState.canvasItems.removeAll()
                status = "编辑区已清空"
            }
        } message: {
            Text("将删除当前编辑区里的所有贴纸。")
        }
        .alert("固化为一张贴纸？", isPresented: $showSolidifyConfirmation) {
            Button("取消", role: .cancel) { }
            Button("固化", role: .destructive) {
                saveDraft(kind: selectedPlay, isSaved: true)
                demoState.solidifySuperSticker(mode: selectedPlay == .fusion ? .fusion : currentMode)
                status = "已固化为一张贴纸，历史已清空"
            }
        } message: {
            Text("所有在编辑区域的贴纸将视为同一张贴纸，清除缓存和历史，无法撤销。")
        }
        .alert("退出画布裁剪？", isPresented: $showCropExitConfirmation) {
            Button("继续裁剪", role: .cancel) { }
            Button("退出", role: .destructive) {
                isCropMode = false
            }
        } message: {
            Text("当前有未应用的画布裁剪，退出前请确认。")
        }
    }

    private var home: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Playground")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                    Text("选择玩法，继续最近项目或新建作品")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 58)
                .padding(.horizontal, 22)

                VStack(spacing: 16) {
                    playCard(.freeStick)
                    playCard(.fusion)
                }

                Color.clear.frame(height: 112)
            }
        }
    }

    private func playCard(_ kind: PlaygroundPlayKind) -> some View {
        GeometryReader { proxy in
            let side = max(260, min(proxy.size.width - 44, 360))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    Button {
                        enterPlay(kind)
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: kind.icon)
                                .font(.system(size: 34, weight: .black))
                                .foregroundStyle(kind.color)
                                .frame(width: 62, height: 62)
                                .background(kind.color.opacity(0.1), in: Circle())

                            Spacer(minLength: 0)

                            Text(kind.title)
                                .font(.system(size: 25, weight: .black, design: .rounded))
                            Text(kind.subtitle)
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Label("进入", systemImage: "arrow.right.circle.fill")
                                .font(.system(size: 13, weight: .black))
                                .foregroundStyle(kind.color)
                        }
                        .padding(16)
                        .frame(width: side, height: side, alignment: .leading)
                        .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(kind.color.opacity(0.18), lineWidth: 1.5))
                        .shadow(color: kind.color.opacity(0.12), radius: 18, x: 0, y: 10)
                    }
                    .buttonStyle(.plain)

                    if !recentDrafts(for: kind).isEmpty {
                        draftGalleryCard(for: kind)
                            .frame(width: side, height: side)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
        .frame(height: 364)
    }

    private func draftGalleryCard(for kind: PlaygroundPlayKind) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.white)

            ForEach(Array(recentDrafts(for: kind).prefix(3).enumerated()), id: \.element.id) { index, draft in
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(index == 0 ? kind.color.opacity(0.14) : .white)
                    .overlay {
                        VStack(spacing: 5) {
                            Image(systemName: draft.isSaved ? "checkmark.seal.fill" : "tray.fill")
                                .font(.system(size: 18, weight: .black))
                            Text("\(draft.itemCount)")
                                .font(.system(size: 11, weight: .black))
                        }
                        .foregroundStyle(kind.color)
                    }
                    .frame(width: 66, height: 78)
                    .rotationEffect(.degrees(Double(index - 1) * 7))
                    .offset(x: CGFloat(index) * 8, y: CGFloat(index) * -4)
                    .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 5)
            }
        }
        .overlay(alignment: .bottomLeading) {
            Text("最近项目")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(kind.color)
                .padding(14)
        }
        .shadow(color: kind.color.opacity(0.1), radius: 16, x: 0, y: 9)
    }

    private func workspace(for kind: PlaygroundPlayKind) -> some View {
        VStack(spacing: 10) {
            workspaceHeader(kind)
                .padding(.top, 54)
                .padding(.horizontal, 18)

            editorStage(kind)
                .padding(.horizontal, 18)

            actionToolRow()
                .padding(.horizontal, 18)

            if isToolLibraryExpanded {
                toolLibrary(kind)
                    .padding(.horizontal, 18)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            stickerTray

            Spacer(minLength: 96)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: isToolLibraryExpanded)
    }

    private func workspaceHeader(_ kind: PlaygroundPlayKind) -> some View {
        HStack(spacing: 10) {
            Button {
                handleBackFromWorkspace()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(kind.color)
                    .frame(width: 42, height: 42)
                    .background(.white, in: Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(kind.title)
                    .font(.system(size: 27, weight: .black, design: .rounded))
                Text(status)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            headerIconButton("tray.full.fill") {
                showDraftBox = true
            }

            headerIconButton("square.and.arrow.down.fill") {
                saveDraft(kind: kind, isSaved: true)
            }
        }
    }

    private func headerIconButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(StickifyTheme.carbonBlack)
                .frame(width: 42, height: 42)
                .background(.white, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func editorStage(_ kind: PlaygroundPlayKind) -> some View {
        GeometryReader { proxy in
            let stageSize = proxy.size
            ZStack {
                stageBackground(for: kind)

                if showsDotGrid {
                    DotGridView()
                }

                ForEach(demoState.canvasItems) { item in
                    PlayableStickerView(
                        item: item,
                        stageSize: stageSize,
                        isFusionMode: kind == .fusion,
                        onChange: { demoState.updateCanvasItem($0) },
                        onDelete: { demoState.canvasItems.removeAll { $0.id == item.id } },
                        onBringToFront: { moveCanvasItem(id: item.id, toFront: true) },
                        onSendToBack: { moveCanvasItem(id: item.id, toFront: false) }
                    )
                }

                if demoState.canvasItems.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: kind.icon)
                            .font(.system(size: 32, weight: .black))
                            .foregroundStyle(kind.color)
                        Text("从底部贴纸库加入贴纸")
                            .font(.system(size: 15, weight: .black))
                    }
                }

                if isCropMode {
                    canvasCropOverlay(kind)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.black.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.1), radius: 18, x: 0, y: 10)
        }
        .aspectRatio(ratio.value, contentMode: .fit)
        .frame(maxHeight: 460)
    }

    @ViewBuilder
    private func stageBackground(for kind: PlaygroundPlayKind) -> some View {
        if kind == .fusion {
            StickerCheckerboard()
        } else if let backdropImageData, let image = UIImage(data: backdropImageData) {
            ZStack {
                Color.white
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }
        } else {
            Color.white
        }
    }

    private func canvasCropOverlay(_ kind: PlaygroundPlayKind) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.white.opacity(0.01))
                .background(.ultraThinMaterial)
                .blur(radius: 22)

            VStack(spacing: 8) {
                Image(systemName: "crop")
                    .font(.system(size: 28, weight: .black))
                Text("画布裁剪模式")
                    .font(.system(size: 14, weight: .black))
                Text("选择裁剪线，应用后改变画布可见区域")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.78))
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(.black.opacity(0.46), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            cropToolbar(kind)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
    }

    private func cropToolbar(_ kind: PlaygroundPlayKind) -> some View {
        HStack(spacing: 8) {
            Picker("裁剪侧", selection: $cropSide) {
                ForEach(CropSide.allCases) { side in
                    Text(side.title).tag(side)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 132)

            Button {
                showCropExitConfirmation = true
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(kind.color, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private func actionToolRow() -> some View {
        HStack(spacing: 12) {
            neutralActionButton(title: "删除", icon: "trash.fill") {
                undoLastSticker()
            }
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                showClearConfirmation = true
            })

            neutralActionButton(title: "工具", icon: isToolLibraryExpanded ? "chevron.up.circle.fill" : "slider.horizontal.3") {
                isToolLibraryExpanded.toggle()
            }

            neutralActionButton(title: "固化", icon: "checkmark.seal.fill") {
                showSolidifyConfirmation = true
            }
            .disabled(demoState.canvasItems.isEmpty)
            .opacity(demoState.canvasItems.isEmpty ? 0.45 : 1)
        }
        .padding(10)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func neutralActionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .black))
                Text(title)
                    .font(.system(size: 11, weight: .black))
            }
            .foregroundStyle(StickifyTheme.carbonBlack)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(StickifyTheme.orderGrey.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func toolLibrary(_ kind: PlaygroundPlayKind) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ratioMenu(kind)
                toggleTool(title: showsDotGrid ? "网格开" : "网格", icon: "circle.grid.3x3.fill", color: kind.color, isOn: showsDotGrid) { showsDotGrid.toggle() }
                toggleTool(title: symmetryEnabled ? "对称开" : "轴对称", icon: "arrow.left.and.right", color: kind.color, isOn: symmetryEnabled) { symmetryEnabled.toggle() }
                toggleTool(title: snapEnabled ? "吸附开" : "吸附", icon: "scope", color: kind.color, isOn: snapEnabled) { snapEnabled.toggle() }

                if kind == .freeStick {
                    toolButton(title: currentMode == .scatter ? "散射" : "堆叠", icon: "switch.2", color: kind.color) {
                        currentMode = currentMode == .scatter ? .stack : .scatter
                        applyLayoutMode()
                    }
                    toolButton(title: "散布", icon: "sparkles", color: kind.color) {
                        scatterStickers(allowsOverlap: currentMode == .stack)
                    }
                    if currentMode == .scatter {
                        toolButton(title: "重力", icon: "arrow.down.circle.fill", color: kind.color) {
                            applyGravityDrop()
                        }
                    }
                } else {
                    toolButton(title: isCropMode ? "退出裁剪" : "画布裁剪", icon: "crop", color: kind.color) {
                        if isCropMode { showCropExitConfirmation = true } else { isCropMode = true }
                    }
                }

                PhotosPicker(selection: $backdropSelection, matching: .images) {
                    toolLabel(title: "背景", icon: "photo.fill", color: kind.color, isOn: false)
                }
                .buttonStyle(.plain)

                toolButton(title: "图片", icon: "plus.rectangle.on.rectangle", color: kind.color) {
                    status = "添加图片入口已打开"
                }
                brushMenu(kind)
            }
            .padding(.vertical, 2)
        }
        .padding(10)
        .background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func ratioMenu(_ kind: PlaygroundPlayKind) -> some View {
        Menu {
            ForEach(CanvasRatio.allCases) { item in
                Button(item.title) { ratio = item }
            }
        } label: {
            toolLabel(title: ratio.title, icon: "aspectratio.fill", color: kind.color, isOn: false)
        }
    }

    private func brushMenu(_ kind: PlaygroundPlayKind) -> some View {
        Menu {
            Picker("画笔", selection: $brushTool) {
                ForEach(BrushTool.allCases) { tool in
                    Text(tool.title).tag(tool)
                }
            }
            Slider(value: $brushWidth, in: 2...24) { Text("粗细") }
            Button("红色") { brushColor = StickifyTheme.energeticRed }
            Button("蓝色") { brushColor = StickifyTheme.classicBlue }
            Button("黑色") { brushColor = StickifyTheme.carbonBlack }
        } label: {
            toolLabel(title: brushTool.title, icon: "paintbrush.pointed.fill", color: kind.color, isOn: false)
        }
    }

    private func toggleTool(title: String, icon: String, color: Color, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            toolLabel(title: title, icon: icon, color: color, isOn: isOn)
        }
        .buttonStyle(.plain)
    }

    private func toolButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            toolLabel(title: title, icon: icon, color: color, isOn: false)
        }
        .buttonStyle(.plain)
    }

    private func toolLabel(title: String, icon: String, color: Color, isOn: Bool) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .black))
            Text(title)
                .font(.system(size: 10, weight: .black))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(isOn ? .white : color)
        .frame(width: 72, height: 56)
        .background(isOn ? color : color.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var stickerTray: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom) {
                selectedCloudChip
                    .onTapGesture { showLibraryPicker = true }

                Text("\(displayedTrayStickers.count)/\(selectedLibraryStickers.count)")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)

                Spacer()
            }
            .padding(.horizontal, 22)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(displayedTrayStickers) { sticker in
                        Button {
                            addSticker(sticker)
                        } label: {
                            StickerChip(sticker: sticker, size: 62)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 22)
            }
        }
    }

    private var selectedCloudChip: some View {
        let library = selectedLibrary
        let skin = library?.skin ?? .sky
        return VStack(spacing: 2) {
            CloudShape()
                .fill(skin.backgroundColor.opacity(0.78))
                .overlay {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 19, weight: .black))
                        .foregroundStyle(skin.primaryColor)
                }
                .frame(width: 76, height: 46)
            Text(library?.name ?? "临时云")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(skin.primaryColor)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
        .frame(width: 92)
    }

    private var libraryPicker: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(demoState.libraries) { library in
                        Button {
                            selectedLibraryId = library.id
                            showLibraryPicker = false
                        } label: {
                            HStack(spacing: 12) {
                                VStack(spacing: 2) {
                                    CloudShape()
                                        .fill(library.skin.backgroundColor.opacity(0.78))
                                        .overlay {
                                            Image(systemName: "cloud.fill")
                                                .font(.system(size: 22, weight: .black))
                                                .foregroundStyle(library.skin.primaryColor)
                                        }
                                        .frame(width: 92, height: 58)
                                    Text(library.name)
                                        .font(.system(size: 11, weight: .black))
                                        .foregroundStyle(library.skin.primaryColor)
                                        .lineLimit(1)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(library.name)
                                        .font(.system(size: 17, weight: .black, design: .rounded))
                                    Text("\(library.stickers.count) stickers")
                                        .font(.system(size: 12, weight: .heavy))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                            .padding(12)
                            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(18)
            }
            .background(StickifyTheme.orderGrey)
            .navigationTitle("选择云库")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var draftBox: some View {
        NavigationStack {
            ScrollView {
                if drafts.isEmpty {
                    ContentUnavailableView("暂无草稿", systemImage: "tray", description: Text("未保存关闭、过去项目和保存项目会出现在这里。"))
                        .padding(.top, 60)
                } else {
                    VStack(spacing: 12) {
                        ForEach(drafts) { draft in
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(draft.kind.color.opacity(0.14))
                                    .overlay {
                                        Image(systemName: draft.kind.icon)
                                            .font(.system(size: 24, weight: .black))
                                            .foregroundStyle(draft.kind.color)
                                    }
                                    .frame(width: 76, height: 76)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(draft.kind.title)
                                        .font(.system(size: 16, weight: .black, design: .rounded))
                                    Text(draft.isSaved ? "最近保存项目" : "最近未保存项目")
                                        .font(.system(size: 12, weight: .heavy))
                                        .foregroundStyle(.secondary)
                                    Text("\(draft.itemCount) 个贴纸")
                                        .font(.system(size: 11, weight: .black))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(12)
                            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                    .padding(18)
                }
            }
            .background(StickifyTheme.orderGrey)
            .navigationTitle("草稿箱")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func enterPlay(_ kind: PlaygroundPlayKind) {
        selectedPlay = kind
        currentMode = kind == .freeStick ? .stack : .fusion
        isCropMode = false
        isToolLibraryExpanded = false
        status = kind.subtitle
    }

    private func handleBackFromWorkspace() {
        if isCropMode {
            showCropExitConfirmation = true
            return
        }
        saveDraft(kind: selectedPlay, isSaved: false)
        selectedPlay = nil
    }

    private func saveDraft(kind: PlaygroundPlayKind?, isSaved: Bool) {
        guard let kind else { return }
        let itemCount = demoState.canvasItems.count
        guard itemCount > 0 || isSaved else { return }
        let draft = PlaygroundDraft(kind: kind, isSaved: isSaved, itemCount: itemCount)
        drafts.removeAll { $0.kind == kind && $0.isSaved == isSaved && $0.itemCount == itemCount }
        drafts.insert(draft, at: 0)
        let saved = Array(drafts.filter(\.isSaved).prefix(5))
        let unsaved = drafts.filter { !$0.isSaved }.prefix(5)
        drafts = Array((saved + Array(unsaved)).prefix(10))
        status = isSaved ? "已保存到草稿箱" : "未保存项目已进入草稿箱"
    }

    private func addSticker(_ sticker: StickerItem) {
        _ = demoState.addStickerToCanvas(sticker)
        if snapEnabled { snapLastStickerToGrid() }
        if symmetryEnabled { addMirroredSticker(from: sticker) }
        if selectedPlay == .freeStick { applyLayoutMode() }
        status = "已添加 \(sticker.fallbackName)"
    }

    private func snapLastStickerToGrid() {
        guard let firstIndex = demoState.canvasItems.indices.first else { return }
        demoState.canvasItems[firstIndex].x = (demoState.canvasItems[firstIndex].x / 24).rounded() * 24
        demoState.canvasItems[firstIndex].y = (demoState.canvasItems[firstIndex].y / 24).rounded() * 24
    }

    private func addMirroredSticker(from sticker: StickerItem) {
        let item = demoState.addStickerToCanvas(sticker)
        if let index = demoState.canvasItems.firstIndex(where: { $0.id == item.id }) {
            demoState.canvasItems[index].x = -item.x
        }
    }

    private func undoLastSticker() {
        guard !demoState.canvasItems.isEmpty else { return }
        demoState.canvasItems.removeFirst()
        status = "已取消上一个添加的贴纸"
    }

    private func applyLayoutMode() {
        guard !demoState.canvasItems.isEmpty else { return }
        if currentMode == .scatter {
            scatterStickers(allowsOverlap: false)
        } else {
            stackStickers()
        }
    }

    private func stackStickers() {
        for index in demoState.canvasItems.indices {
            demoState.canvasItems[index].x = CGFloat(index) * 18 - 36
            demoState.canvasItems[index].y = CGFloat(index) * -14 + 28
            demoState.canvasItems[index].rotationDegrees = Double(index * 6) - 10
        }
        status = "堆叠模式已应用"
    }

    private func scatterStickers(allowsOverlap: Bool) {
        let spread: CGFloat = allowsOverlap ? CGFloat(spacingJitter) : CGFloat(spacingJitter + 46)
        for index in demoState.canvasItems.indices {
            demoState.canvasItems[index].x = CGFloat.random(in: -spread...spread)
            demoState.canvasItems[index].y = CGFloat.random(in: -spread...spread)
            demoState.canvasItems[index].scale = CGFloat.random(in: 0.86...(1 + sizeJitter / 100))
            let rotation = Double.random(in: -rotationJitter...rotationJitter)
            demoState.canvasItems[index].rotationDegrees = rotationDirection == .counterclockwise ? -abs(rotation) : (rotationDirection == .clockwise ? abs(rotation) : rotation)
        }
        status = allowsOverlap ? "堆叠散布已应用" : "散射散布已应用"
    }

    private func applyGravityDrop() {
        for index in demoState.canvasItems.indices {
            demoState.canvasItems[index].y += CGFloat(32 + index * 8)
        }
        status = "重力效果已应用"
    }

    private func moveCanvasItem(id: UUID, toFront: Bool) {
        guard let index = demoState.canvasItems.firstIndex(where: { $0.id == id }) else { return }
        let item = demoState.canvasItems.remove(at: index)
        if toFront {
            demoState.canvasItems.insert(item, at: 0)
        } else {
            demoState.canvasItems.append(item)
        }
    }

    private func recentDrafts(for kind: PlaygroundPlayKind) -> [PlaygroundDraft] {
        drafts.filter { $0.kind == kind }
    }

    private func loadBackdropPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            let data = try? await item.loadTransferable(type: Data.self)
            await MainActor.run {
                backdropImageData = data
                backdropSelection = nil
                status = data == nil ? "图片读取失败" : "背景图片已添加"
            }
        }
    }
}

private struct PlaygroundDraft: Identifiable, Equatable {
    var id = UUID()
    var kind: PlaygroundPlayKind
    var isSaved: Bool
    var itemCount: Int
}

private enum PlaygroundPlayKind: Identifiable, Equatable {
    case freeStick
    case fusion

    var id: String { title }
    var title: String { self == .freeStick ? "玩法1 随心贴" : "玩法2 融合" }
    var subtitle: String { self == .freeStick ? "堆叠与散射工具库，自由排列贴纸" : "透明背景融合与画布裁剪工具" }
    var icon: String { self == .freeStick ? "square.3.layers.3d.top.filled" : "drop.fill" }
    var color: Color { self == .freeStick ? StickifyTheme.energeticRed : StickifyTheme.classicBlue }
}

private enum CanvasRatio: String, CaseIterable, Identifiable {
    case square
    case portrait
    case story
    var id: String { rawValue }
    var title: String { self == .square ? "1:1" : (self == .portrait ? "3:4" : "9:16") }
    var value: CGFloat { self == .square ? 1 : (self == .portrait ? 0.75 : 0.5625) }
}

private enum RotationDirection: String, CaseIterable, Identifiable {
    case mixed
    case clockwise
    case counterclockwise
    var id: String { rawValue }
}

private enum BrushTool: String, CaseIterable, Identifiable {
    case sticker
    case crayon
    case pen
    var id: String { rawValue }
    var title: String { self == .sticker ? "贴纸画笔" : (self == .crayon ? "蜡笔" : "钢笔") }
}

private enum CropSide: String, CaseIterable, Identifiable {
    case left
    case right
    var id: String { rawValue }
    var title: String { self == .right ? "右侧" : "左侧" }
}

private struct DotGridView: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 24
            for x in stride(from: CGFloat(0), through: size.width, by: step) {
                for y in stride(from: CGFloat(0), through: size.height, by: step) {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2.5, height: 2.5)), with: .color(Color.black.opacity(0.12)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct StickerCheckerboard: View {
    var body: some View {
        Canvas { context, size in
            let square: CGFloat = 12
            for row in 0..<Int(ceil(size.height / square)) {
                for column in 0..<Int(ceil(size.width / square)) where (row + column).isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: CGFloat(column) * square, y: CGFloat(row) * square, width: square, height: square)), with: .color(Color.black.opacity(0.06)))
                }
            }
        }
        .background(Color.white.opacity(0.12))
    }
}

private struct PlayableStickerView: View {
    var item: CanvasStickerItem
    var stageSize: CGSize
    var isFusionMode: Bool
    var onChange: (CanvasStickerItem) -> Void
    var onDelete: () -> Void
    var onBringToFront: () -> Void
    var onSendToBack: () -> Void

    @State private var draft: CanvasStickerItem
    @State private var gestureScale: CGFloat = 1
    @State private var gestureRotation: Angle = .zero

    init(item: CanvasStickerItem, stageSize: CGSize, isFusionMode: Bool, onChange: @escaping (CanvasStickerItem) -> Void, onDelete: @escaping () -> Void, onBringToFront: @escaping () -> Void, onSendToBack: @escaping () -> Void) {
        self.item = item
        self.stageSize = stageSize
        self.isFusionMode = isFusionMode
        self.onChange = onChange
        self.onDelete = onDelete
        self.onBringToFront = onBringToFront
        self.onSendToBack = onSendToBack
        _draft = State(initialValue: item)
    }

    var body: some View {
        StickerChip(sticker: displaySticker, size: 86)
            .scaleEffect(draft.scale * gestureScale)
            .rotationEffect(.degrees(draft.rotationDegrees) + gestureRotation)
            .shadow(color: isFusionMode ? StickifyTheme.classicBlue.opacity(0.18) : .black.opacity(0.14), radius: 10, x: 0, y: 7)
            .position(x: stageSize.width / 2 + draft.x, y: stageSize.height / 2 + draft.y)
            .gesture(dragGesture)
            .simultaneousGesture(scaleGesture)
            .simultaneousGesture(rotationGesture)
            .contextMenu {
                Button("置顶", systemImage: "arrow.up.to.line") { onBringToFront() }
                Button("置底", systemImage: "arrow.down.to.line") { onSendToBack() }
                Button("删除", systemImage: "trash", role: .destructive) { onDelete() }
            }
            .onChange(of: item) { _, newValue in draft = newValue }
    }

    private var displaySticker: StickerItem {
        var sticker = draft.sticker
        sticker.angle = 0
        return sticker
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                draft.x = item.x + value.translation.width
                draft.y = item.y + value.translation.height
            }
            .onEnded { _ in onChange(draft) }
    }

    private var scaleGesture: some Gesture {
        MagnificationGesture()
            .onChanged { gestureScale = $0 }
            .onEnded { value in
                draft.scale = min(max(item.scale * value, 0.45), 1.9)
                gestureScale = 1
                onChange(draft)
            }
    }

    private var rotationGesture: some Gesture {
        RotationGesture()
            .onChanged { gestureRotation = $0 }
            .onEnded { value in
                draft.rotationDegrees = item.rotationDegrees + value.degrees
                gestureRotation = .zero
                onChange(draft)
            }
    }
}
