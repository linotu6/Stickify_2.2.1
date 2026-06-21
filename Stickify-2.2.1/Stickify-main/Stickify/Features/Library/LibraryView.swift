import Photos
import SwiftUI

struct LibraryView: View {
    @Binding var demoState: StickifyDemoState
    @State private var selectedLibraryId: UUID?
    @State private var query = ""
    @State private var selectedStickers: Set<UUID> = []
    @State private var previewSticker: StickerItem?
    @State private var showNewLibrary = false
    @State private var showDeleteConfirmation = false
    @State private var newLibraryName = ""
    @State private var draftLibraryName = ""
    @State private var draftLibrarySkin: CloudSkin = .sky
    @State private var statusMessage = "长按贴纸进入多选"
    @State private var isSelecting = false
    @State private var selectedBatchStyle: StickerVisualStyle = .whiteBorder
    @State private var renderingBatchStyle: StickerVisualStyle?
    @State private var batchStyleTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .bottom) {
            if selectedLibraryId == nil {
                skyHub
            } else if let library = currentLibrary {
                vault(for: library)
            } else {
                skyHub
            }

            if isSelecting {
                editorPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .foregroundStyle(StickifyTheme.carbonBlack)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: selectedStickers)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: selectedLibraryId)
        .fullScreenCover(item: $previewSticker) { sticker in
            StickerDetailSheet(sticker: sticker)
            { id, name, visualStyle in
                if let updated = demoState.updateStickerDetails(id: id, name: name, visualStyle: visualStyle) {
                    previewSticker = updated
                }
            } onDelete: { id in
                demoState.deleteSticker(id: id)
                previewSticker = nil
            }
        }
        .sheet(isPresented: $showNewLibrary) {
            NavigationStack {
                Form {
                    TextField("例如：旅行灵感", text: $newLibraryName)
                }
                .navigationTitle("新建灵感库")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showNewLibrary = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("创建") {
                            createLibrary()
                        }
                        .disabled(newLibraryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .presentationDetents([.height(220)])
        }
        .alert("删除已选中贴纸？", isPresented: $showDeleteConfirmation) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                deleteSelectedStickers()
            }
        } message: {
            Text("将从贴纸库中删除 \(selectedStickers.count) 个贴纸。")
        }
        .onDisappear {
            batchStyleTask?.cancel()
            renderingBatchStyle = nil
        }
    }

    private var currentLibrary: StickerLibrary? {
        guard let selectedLibraryId else { return nil }
        return demoState.libraries.first { $0.id == selectedLibraryId }
    }

    private var vaultStickers: [StickerItem] {
        demoState.stickers(in: selectedLibraryId, query: query)
    }

    private var selectedItems: [StickerItem] {
        demoState.libraries.flatMap(\.stickers).filter { selectedStickers.contains($0.id) }
    }

    private var skyHub: some View {
        ZStack {
            StickifyTheme.skyBlue.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                hubHeader
                    .padding(.top, 58)
                    .padding(.horizontal, 22)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 2),
                    spacing: 18
                ) {
                    ForEach(demoState.cloudHubSlots(maxSlots: 8)) { slot in
                        switch slot {
                        case .library(let library):
                            Button {
                                enterVault(library)
                            } label: {
                                CloudLibraryCard(library: library)
                            }
                            .buttonStyle(.plain)
                        case .create:
                            Button {
                                showNewLibrary = true
                            } label: {
                                CreateCloudCard()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 22)

                Spacer(minLength: 118)
            }
        }
    }

    private var hubHeader: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 7) {
                Text("The Sky Hub")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                Text("天空中转站")
                    .font(.system(size: 15, weight: .heavy))
            }

            Spacer()

            Text("\(demoState.libraries.count) clouds")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(.white)
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .background(StickifyTheme.classicBlue, in: Capsule())
        }
    }

    private func vault(for library: StickerLibrary) -> some View {
        ZStack {
            StickifyTheme.orderGrey.ignoresSafeArea()

            VStack(spacing: 0) {
                vaultHeader(for: library)
                    .padding(.top, 58)
                    .padding(.horizontal, 22)

                vaultControls
                    .padding(.top, 16)
                    .padding(.horizontal, 22)

                stickerGrid
            }
        }
    }

    private func vaultHeader(for library: StickerLibrary) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                selectedLibraryId = nil
                selectedStickers.removeAll()
                isSelecting = false
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(StickifyTheme.classicBlue)
                    .frame(width: 44, height: 44)
                    .background(.white, in: Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(library.name)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .lineLimit(1)
                Text("\(library.stickers.count) stickers")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isSelecting {
                Text("选择模式")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(StickifyTheme.classicBlue)

                Button("取消") {
                    exitSelectionMode()
                }
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(StickifyTheme.classicBlue)

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(StickifyTheme.energeticRed)
                        .frame(width: 34, height: 34)
                        .background(.white, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(selectedStickers.isEmpty)
            } else {
                Button {
                    isSelecting = true
                    selectedStickers.removeAll()
                    syncLibraryDraft(library)
                statusMessage = "库设置将应用到整个灵感库"
                } label: {
                    Label("库设置", systemImage: "gearshape.fill")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 11)
                        .background(StickifyTheme.classicBlue, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var vaultControls: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(.secondary)
            TextField("搜索贴纸", text: $query)
                .font(.system(size: 15, weight: .heavy))
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(.white, in: Capsule())
    }

    private var stickerGrid: some View {
        ScrollView {
            if vaultStickers.isEmpty {
                ContentUnavailableView("没有找到贴纸", systemImage: "sparkles", description: Text("换一个搜索词或从 Capture 制作新贴纸。"))
                    .padding(.top, 72)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 14) {
                    ForEach(vaultStickers) { sticker in
                        Button {
                            if isSelecting || !selectedStickers.isEmpty {
                                isSelecting = true
                                toggle(sticker)
                            } else {
                                previewSticker = sticker
                            }
                        } label: {
                            LibraryStickerCell(
                                sticker: sticker,
                                displayName: demoState.displayName(for: sticker, in: selectedLibraryId),
                                isSelected: selectedStickers.contains(sticker.id),
                                isSelecting: isSelecting
                            )
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(LongPressGesture(minimumDuration: 0.3).onEnded { _ in
                            isSelecting = true
                            toggle(sticker)
                        })
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, isSelecting ? 236 : 118)
            }
        }
    }

    private var editorPanel: some View {
        VStack(spacing: 13) {
            HStack {
                Text(selectedStickers.isEmpty ? "库设置" : "\(selectedStickers.count) selected")
                    .font(.system(size: 15, weight: .black))
                Text(statusMessage)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("完成") {
                    exitSelectionMode()
                }
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(StickifyTheme.classicBlue)
            }

            if selectedStickers.isEmpty {
                libraryAttributePanel
            }

            HStack(spacing: 10) {
                editorButton("克隆", "plus.square.on.square", isEnabled: !selectedStickers.isEmpty && renderingBatchStyle == nil) {
                    cloneSelected()
                }
                editorButton(
                    selectedStickers.isEmpty ? "整库应用" : "选中应用",
                    "paintpalette.fill",
                    value: renderingBatchStyle == nil ? selectedBatchStyle.title : "生成中",
                    isEnabled: renderingBatchStyle == nil
                ) {
                    applySelectedStyle(selectedBatchStyle)
                }
            }

            StickerVisualStylePicker(selectedStyle: selectedBatchStyle, compact: true, renderingStyle: renderingBatchStyle) { style in
                selectedBatchStyle = style
                applySelectedStyle(style)
            }
        }
        .padding(18)
        .padding(.bottom, 86)
        .background(.white.opacity(0.97), in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
        .shadow(color: .black.opacity(0.16), radius: 20, x: 0, y: -8)
    }

    private var libraryAttributePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("库属性")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(.secondary)

            TextField("云库名称", text: $draftLibraryName)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    commitLibraryAttributes()
                }
                .onChange(of: draftLibraryName) { _, _ in
                    commitLibraryAttributes()
                }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CloudSkin.allCases) { skin in
                        Button {
                            draftLibrarySkin = skin
                            commitLibraryAttributes()
                        } label: {
                            HStack(spacing: 7) {
                                Circle()
                                    .fill(skin.primaryColor)
                                    .frame(width: 13, height: 13)
                                Text(skin.title)
                            }
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(draftLibrarySkin == skin ? .white : StickifyTheme.carbonBlack)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .background(draftLibrarySkin == skin ? skin.primaryColor : skin.backgroundColor.opacity(0.62), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .background((currentLibrary?.skin.backgroundColor ?? StickifyTheme.skyBlue).opacity(0.42), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
    private func editorButton(
        _ title: String,
        _ icon: String,
        value: String? = nil,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .black))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .black))
                    if let value {
                        Text(value)
                            .font(.system(size: 10, weight: .heavy))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.5))
            .padding(.horizontal, 13)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(isEnabled ? StickifyTheme.classicBlue : Color.gray.opacity(0.42), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func enterVault(_ library: StickerLibrary) {
        selectedLibraryId = library.id
        syncLibraryDraft(library)
        query = ""
        selectedStickers.removeAll()
        isSelecting = false
    }

    private func syncLibraryDraft(_ library: StickerLibrary) {
        draftLibraryName = library.name
        draftLibrarySkin = library.skin
    }

    private func commitLibraryAttributes() {
        guard let library = currentLibrary else { return }
        demoState.updateLibraryAttributes(id: library.id, name: draftLibraryName, skin: draftLibrarySkin)
    }

    private func toggle(_ sticker: StickerItem) {
        if selectedStickers.contains(sticker.id) {
            selectedStickers.remove(sticker.id)
        } else {
            selectedStickers.insert(sticker.id)
        }
    }

    private func exitSelectionMode() {
        selectedStickers.removeAll()
        isSelecting = false
        statusMessage = "长按贴纸进入多选"
    }

    private func deleteSelectedStickers() {
        selectedStickers.forEach { id in
            demoState.deleteSticker(id: id)
        }
        exitSelectionMode()
    }

    private func cloneSelected() {
        guard let library = currentLibrary else { return }
        selectedItems.forEach { demoState.clone($0, in: library) }
        selectedLibraryId = library.id
        statusMessage = "已克隆 \(selectedItems.count) 个贴纸"
        selectedStickers.removeAll()
    }

    private func applySelectedStyle(_ style: StickerVisualStyle) {
        guard renderingBatchStyle == nil else { return }
        let targetStickers: [StickerItem]
        let appliesToWholeLibrary = selectedStickers.isEmpty

        if selectedStickers.isEmpty {
            guard let library = currentLibrary else { return }
            targetStickers = library.stickers
        } else {
            targetStickers = demoState.uniqueStickers(matching: selectedStickers)
        }

        guard !targetStickers.isEmpty else {
            statusMessage = "没有可更改风格的图片贴纸"
            return
        }

        renderingBatchStyle = style
        statusMessage = "正在生成 \(style.title)…"
        batchStyleTask?.cancel()
        batchStyleTask = Task {
            let updates = await Task.detached(priority: .userInitiated) {
                StickifyDemoState.renderedVisualStyleUpdates(style: style, stickers: targetStickers)
            }.value

            guard !Task.isCancelled else { return }

            let changedCount = demoState.applyVisualStyle(style, using: updates)
            renderingBatchStyle = nil

            if changedCount == 0 {
                statusMessage = "没有可更改风格的图片贴纸"
            } else if appliesToWholeLibrary {
                statusMessage = "已将 \(style.title) 应用到 \(changedCount) 个贴纸"
            } else {
                statusMessage = "已将 \(style.title) 应用到选中贴纸"
            }
        }
    }

    private func createLibrary() {
        let createdLibrary = demoState.addCloud(named: newLibraryName)
        if let createdLibrary {
            selectedLibraryId = createdLibrary.id
        }
        selectedStickers.removeAll()
        isSelecting = false
        newLibraryName = ""
        showNewLibrary = false
    }

}

private struct CloudLibraryCard: View {
    var library: StickerLibrary

    var body: some View {
        CloudCard(tint: library.skin.backgroundColor) {
            VStack(spacing: 6) {
                Text(library.name)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(library.skin.primaryColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.72)
                Text("\(library.stickers.count) stickers")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(StickifyTheme.carbonBlack.opacity(0.62))
            }
            .padding(.horizontal, 14)
        }
        .frame(height: 112)
        .accessibilityLabel("\(library.name), \(library.stickers.count) stickers")
    }
}

private struct CreateCloudCard: View {
    var body: some View {
        CloudCard(dashed: true) {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .black))
                    .foregroundStyle(StickifyTheme.classicBlue)
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.72), in: Circle())
                Text("新建云")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(StickifyTheme.carbonBlack)
            }
        }
        .frame(height: 112)
        .accessibilityLabel("新建灵感库")
    }
}

private struct LibraryStickerCell: View {
    var sticker: StickerItem
    var displayName: String
    var isSelected: Bool
    var isSelecting: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                StickerChip(sticker: sticker, size: 78, isSelected: false)
                    .modifier(LibrarySelectionJiggle(isActive: isSelecting))
                    .offset(
                        x: min(sticker.cloneOffset, 20),
                        y: -min(sticker.cloneOffset, 20)
                    )
            }
            .frame(width: 96, height: 88)

            Text(displayName)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(StickifyTheme.carbonBlack)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(isSelected ? 1 : 0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.green, lineWidth: 4)
            }
        }
    }
}

private struct LibrarySelectionJiggle: ViewModifier {
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

private struct StickerVisualStylePicker: View {
    var selectedStyle: StickerVisualStyle
    var compact: Bool
    var renderingStyle: StickerVisualStyle?
    var onSelect: (StickerVisualStyle) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(StickerVisualStyle.allCases) { style in
                    Button {
                        onSelect(style)
                    } label: {
                        VStack(spacing: compact ? 4 : 6) {
                            if renderingStyle == style {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(selectedStyle == style ? .white : StickifyTheme.classicBlue)
                            } else {
                                Image(systemName: style.icon)
                                    .font(.system(size: compact ? 14 : 17, weight: .black))
                            }
                            Text(style.title)
                                .font(.system(size: compact ? 10 : 11, weight: .black))
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                        }
                        .foregroundStyle(selectedStyle == style ? .white : StickifyTheme.carbonBlack)
                        .frame(width: compact ? 76 : 88, height: compact ? 54 : 62)
                        .background(selectedStyle == style ? StickifyTheme.classicBlue : Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(.black.opacity(selectedStyle == style ? 0 : 0.08), lineWidth: 1)
                        )
                        .opacity(renderingStyle == nil || renderingStyle == style ? 1 : 0.48)
                    }
                    .buttonStyle(.plain)
                    .disabled(renderingStyle != nil)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct StickerDetailSheet: View {
    var sticker: StickerItem
    var onSave: (UUID, String, StickerVisualStyle) -> Void
    var onDelete: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var styleRenderController = StickerStyleRenderController()
    @State private var draftName: String
    @State private var draftStyle: StickerVisualStyle
    @State private var draftPreviewData: Data?
    @State private var photoStatus: String?
    @State private var exportURL: URL?
    @State private var renderTask: Task<Void, Never>?

    init(
        sticker: StickerItem,
        onSave: @escaping (UUID, String, StickerVisualStyle) -> Void,
        onDelete: @escaping (UUID) -> Void
    ) {
        self.sticker = sticker
        self.onSave = onSave
        self.onDelete = onDelete
        _draftName = State(initialValue: sticker.name)
        _draftStyle = State(initialValue: sticker.visualStyle)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    stickerPreview
                        .padding(.top, 26)

                    VStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("自定义名称")
                                .font(.system(size: 12, weight: .black))
                                .foregroundStyle(.secondary)
                            TextField("留空则使用自动编号", text: $draftName)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("风格")
                                .font(.system(size: 12, weight: .black))
                                .foregroundStyle(.secondary)
                            StickerVisualStylePicker(selectedStyle: draftStyle, compact: false, renderingStyle: styleRenderController.renderingStyle) { style in
                                draftStyle = style
                                renderDraftPreview(style)
                            }
                            if styleRenderController.renderingStyle != nil {
                                Label("正在生成预览", systemImage: "paintbrush.pointed.fill")
                                    .font(.system(size: 12, weight: .black))
                                    .foregroundStyle(StickifyTheme.classicBlue)
                            }
                        }

                        Label(sourceText, systemImage: sourceIcon)
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(StickifyTheme.classicBlue, in: Capsule())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(18)
                    .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                    VStack(spacing: 10) {
                        Button {
                            saveEdits()
                        } label: {
                            Label("保存名称", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 15, weight: .black))
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .background(StickifyTheme.classicBlue, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .opacity(styleRenderController.renderingStyle == nil ? 1 : 0.5)
                        .disabled(styleRenderController.renderingStyle != nil)

                        HStack(spacing: 10) {
                            Button {
                                saveToPhotos()
                            } label: {
                                Label("存到相册", systemImage: "photo.badge.arrow.down")
                                    .font(.system(size: 13, weight: .black))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(StickifyTheme.carbonBlack)
                            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .disabled(currentExportData == nil)

                            if let exportURL {
                                ShareLink(item: exportURL) {
                                    Label("导出文件", systemImage: "square.and.arrow.up")
                                        .font(.system(size: 13, weight: .black))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 48)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(StickifyTheme.carbonBlack)
                                .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            } else {
                                Button {
                                    photoStatus = "这个示例贴纸没有可导出的 PNG 文件"
                                } label: {
                                    Label("导出文件", systemImage: "square.and.arrow.up")
                                        .font(.system(size: 13, weight: .black))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 48)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(StickifyTheme.carbonBlack.opacity(0.46))
                                .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        }

                        if let photoStatus {
                            Text(photoStatus)
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button(role: .destructive) {
                            onDelete(sticker.id)
                            dismiss()
                        } label: {
                            Label("删除贴纸", systemImage: "trash.fill")
                                .font(.system(size: 14, weight: .black))
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(StickifyTheme.energeticRed)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 34)
            }
            .background(StickifyTheme.orderGrey)
            .navigationTitle("贴纸详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear {
                exportURL = makeExportURL()
                renderDraftPreview(draftStyle)
            }
            .onDisappear {
                renderTask?.cancel()
            }
        }
    }

    @ViewBuilder
    private var stickerPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(StickifyTheme.carbonBlack)
                .frame(height: 350)

            if let image = draftPreviewImage ?? sticker.generatedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(28)
                    .frame(maxWidth: .infinity)
                    .frame(height: 350)
            } else {
                StickerChip(sticker: sticker, size: 230)
            }
        }
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 4) {
                Text(detailTitle)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }
            .padding(18)
        }
    }

    private var detailTitle: String {
        let trimmedName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "自动编号" : trimmedName
    }

    private func saveEdits() {
        onSave(sticker.id, draftName, draftStyle)
        exportURL = makeExportURL()
        photoStatus = "已更新贴纸名称与风格"
    }

    private var draftPreviewImage: UIImage? {
        guard let draftPreviewData else { return nil }
        return UIImage(data: draftPreviewData)
    }

    private func renderDraftPreview(_ style: StickerVisualStyle) {
        renderTask?.cancel()
        guard let sourceData = sticker.originalImageData ?? sticker.imageData else {
            draftPreviewData = nil
            exportURL = nil
            return
        }

        renderTask = Task {
            let renderedData = await styleRenderController.render(sourceData: sourceData, style: style)
            guard !Task.isCancelled else { return }
            draftPreviewData = renderedData
            exportURL = makeExportURL()
        }
    }

    private func saveToPhotos() {
        guard let data = currentExportData else {
            photoStatus = "这个示例贴纸没有可保存的 PNG 文件"
            return
        }

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    photoStatus = "没有相册写入权限"
                }
                return
            }

            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    photoStatus = success ? "已保存到相册" : (error?.localizedDescription ?? "保存到相册失败")
                }
            }
        }
    }

    private func makeExportURL() -> URL? {
        guard let data = currentExportData else { return nil }
        let fileName = sanitizedFileName(from: sticker.name)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)
            .appendingPathExtension("png")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            photoStatus = error.localizedDescription
            return nil
        }
    }

    private var currentExportData: Data? {
        draftPreviewData ?? sticker.imageData
    }

    private var sourceText: String {
        switch sticker.source {
        case .demo:
            return "Demo seed"
        case .camera:
            return "来自相机"
        case .photoLibrary:
            return "来自相册"
        case .playground:
            return "来自 Playground"
        }
    }

    private var sourceIcon: String {
        switch sticker.source {
        case .camera:
            return "camera.fill"
        case .photoLibrary:
            return "photo.fill"
        case .playground:
            return "sparkles"
        case .demo:
            return "shippingbox.fill"
        }
    }

    private func sanitizedFileName(from name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let characters = name.map { character in
            character.unicodeScalars.allSatisfy { allowed.contains($0) } ? character : "-"
        }
        let sanitized = String(characters).trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "Stickify Sticker" : sanitized
    }
}

private extension StickerItem {
    var generatedImage: UIImage? {
        guard let imageData else { return nil }
        return UIImage(data: imageData)
    }
}



