import CoreImage
import CoreImage.CIFilterBuiltins
import Combine
import Foundation
import SwiftUI
import UIKit

enum StickerSource: String, Equatable {
    case demo
    case camera
    case photoLibrary
    case playground
}

enum CameraOriginalCacheAction: Equatable {
    case keep
    case delete
}

enum CameraOriginalCachePreference: String, Codable, Equatable {
    case askEveryTime
    case deleteWithoutAsking
    case keepWithoutAsking

    var shouldAsk: Bool {
        self == .askEveryTime
    }

    var defaultAction: CameraOriginalCacheAction? {
        switch self {
        case .askEveryTime:
            nil
        case .deleteWithoutAsking:
            .delete
        case .keepWithoutAsking:
            .keep
        }
    }

    static func preference(after action: CameraOriginalCacheAction, rememberChoice: Bool) -> CameraOriginalCachePreference {
        guard rememberChoice else { return .askEveryTime }

        switch action {
        case .keep:
            return .keepWithoutAsking
        case .delete:
            return .deleteWithoutAsking
        }
    }
}

struct CameraOriginalCacheCoordinator {
    var preference: CameraOriginalCachePreference
    var saveOriginalToPhotos: (Data) -> Void

    mutating func handleOriginalPhotoData(
        _ data: Data?,
        action: CameraOriginalCacheAction?,
        rememberChoice: Bool
    ) -> CameraOriginalCachePreference {
        let resolvedAction = action ?? preference.defaultAction

        if resolvedAction == .keep, let data {
            saveOriginalToPhotos(data)
        }

        if let action {
            preference = CameraOriginalCachePreference.preference(after: action, rememberChoice: rememberChoice)
        }

        return preference
    }
}

struct StickerFlightPath: Equatable {
    var start: CGPoint
    var target: CGPoint

    init(captureFrame: CGRect, targetFrame: CGRect, subjectBoundingBox: CGRect?) {
        start = Self.startPoint(in: captureFrame, subjectBoundingBox: subjectBoundingBox)
        target = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
    }

    static func defaultCaptureFrame(in containerSize: CGSize) -> CGRect {
        guard containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }

        return CGRect(origin: .zero, size: containerSize)
    }

    private static func startPoint(in captureFrame: CGRect, subjectBoundingBox: CGRect?) -> CGPoint {
        guard let subjectBoundingBox else {
            return CGPoint(x: captureFrame.midX, y: captureFrame.midY)
        }

        return CGPoint(
            x: captureFrame.minX + subjectBoundingBox.midX * captureFrame.width,
            y: captureFrame.minY + subjectBoundingBox.midY * captureFrame.height
        )
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case capture
    case library
    case playground

    var id: String { rawValue }

    var title: String {
        switch self {
        case .capture: "Capture"
        case .library: "Library"
        case .playground: "Play"
        }
    }

    var icon: String {
        switch self {
        case .capture: "camera.fill"
        case .library: "square.grid.2x2.fill"
        case .playground: "play.fill"
        }
    }
}

struct StickerItem: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var symbolName: String
    var angle: Double = 0
    var cloneOffset: CGFloat = 0
    var imageData: Data?
    var originalImageData: Data?
    var visualStyle: StickerVisualStyle = .whiteBorder
    var source: StickerSource = .demo

    var hasCustomName: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var fallbackName: String {
        hasCustomName ? name : "贴纸"
    }

    func copy(offsetAngle: Double = 8, offsetPixels: CGFloat = 10) -> StickerItem {
        StickerItem(
            name: name,
            symbolName: symbolName,
            angle: angle + offsetAngle,
            cloneOffset: cloneOffset + offsetPixels,
            imageData: imageData,
            originalImageData: originalImageData,
            visualStyle: visualStyle,
            source: source
        )
    }
}

enum CloudSkin: String, CaseIterable, Identifiable, Codable {
    case sky
    case mint
    case coral
    case violet
    case graphite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sky: "天空蓝"
        case .mint: "薄荷绿"
        case .coral: "珊瑚红"
        case .violet: "紫罗兰"
        case .graphite: "石墨黑"
        }
    }

    var primaryColor: Color {
        switch self {
        case .sky: StickifyTheme.classicBlue
        case .mint: Color(hex: 0x14A56B)
        case .coral: StickifyTheme.energeticRed
        case .violet: Color(hex: 0x7A5CFF)
        case .graphite: StickifyTheme.carbonBlack
        }
    }

    var backgroundColor: Color {
        switch self {
        case .sky: StickifyTheme.skyBlue
        case .mint: Color(hex: 0xBFF5DD)
        case .coral: Color(hex: 0xFFD4CC)
        case .violet: Color(hex: 0xDDD5FF)
        case .graphite: Color(hex: 0xD8D8D8)
        }
    }
}

struct StickerLibrary: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var stickers: [StickerItem]
    var skin: CloudSkin = .sky
}

enum CloudHubSlot: Identifiable, Equatable {
    case library(StickerLibrary)
    case create

    var id: String {
        switch self {
        case .library(let library):
            return library.id.uuidString
        case .create:
            return "create-cloud"
        }
    }

    var library: StickerLibrary? {
        guard case .library(let library) = self else { return nil }
        return library
    }

    var isCreateSlot: Bool {
        self == .create
    }
}

enum StickerVisualStyle: String, CaseIterable, Identifiable {
    case whiteBorder
    case comicLine
    case pixel
    case neon
    case duotoneStamp
    case retroPoster
    case pencilSketch
    case brightPop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .whiteBorder: "白边贴纸"
        case .comicLine: "漫画线稿"
        case .pixel: "像素贴纸"
        case .neon: "霓虹描边"
        case .duotoneStamp: "双色印章"
        case .retroPoster: "复古海报"
        case .pencilSketch: "黑白素描"
        case .brightPop: "亮色 Pop"
        }
    }

    var icon: String {
        switch self {
        case .whiteBorder: "seal.fill"
        case .comicLine: "scribble.variable"
        case .pixel: "squareshape.split.3x3"
        case .neon: "bolt.fill"
        case .duotoneStamp: "circle.lefthalf.filled"
        case .retroPoster: "rectangle.on.rectangle.angled"
        case .pencilSketch: "pencil.tip"
        case .brightPop: "paintpalette.fill"
        }
    }
}

struct StickerVisualStyleUpdate {
    var stickerId: UUID
    var sourceData: Data
    var imageData: Data
}

enum PlaygroundMode: String, CaseIterable, Identifiable {
    case stack = "堆叠"
    case fusion = "融合"
    case scatter = "散射"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .stack: "square.3.layers.3d.top.filled"
        case .fusion: "drop.fill"
        case .scatter: "sparkles"
        }
    }
}

struct PlaygroundScatterSettings: Equatable {
    var allowsStacking = true
    var hasGap = true
    var gravityEnabled = false

    var isDollMachineMode: Bool {
        gravityEnabled && !hasGap && !allowsStacking
    }

    var summary: String {
        isDollMachineMode ? "娃娃机模式" : "散射参数"
    }
}

struct CanvasStickerItem: Identifiable, Equatable {
    var id = UUID()
    var sticker: StickerItem
    var x: CGFloat
    var y: CGFloat
    var scale: CGFloat
    var rotationDegrees: Double
}

struct StickifyDemoState {
    var shelf: [StickerItem]
    var libraries: [StickerLibrary]
    var canvasItems: [CanvasStickerItem]
    var scannedSticker: StickerItem
    var superStickerCount = 0
    var cameraOriginalCachePreference: CameraOriginalCachePreference = .askEveryTime

    var shouldAskCleanup: Bool {
        get { cameraOriginalCachePreference.shouldAsk }
        set { cameraOriginalCachePreference = newValue ? .askEveryTime : .deleteWithoutAsking }
    }

    mutating func applyCameraOriginalCacheChoice(_ action: CameraOriginalCacheAction, rememberChoice: Bool) {
        cameraOriginalCachePreference = CameraOriginalCachePreference.preference(after: action, rememberChoice: rememberChoice)
    }

    mutating func collectScannedSticker() {
        let collected = scannedSticker.copy(offsetAngle: Double.random(in: -10...10))
        shelf.insert(collected, at: 0)
        if !libraries.isEmpty {
            libraries[0].stickers.insert(collected, at: 0)
        }
    }

    @discardableResult
    mutating func addGeneratedSticker(
        imageData: Data?,
        source: StickerSource,
        originalImageData: Data? = nil,
        visualStyle: StickerVisualStyle = .whiteBorder
    ) -> StickerItem {
        let baseImageData = originalImageData ?? imageData
        let renderedImageData = Self.renderedImageData(
            from: baseImageData,
            style: visualStyle
        ) ?? imageData
        let sticker = StickerItem(
            name: "",
            symbolName: source == .photoLibrary ? "photo.fill" : "camera.fill",
            angle: Double.random(in: -6...6),
            imageData: renderedImageData,
            originalImageData: baseImageData,
            visualStyle: visualStyle,
            source: source
        )
        shelf.insert(sticker, at: 0)
        ensurePrimaryLibrary()
        libraries[0].stickers.insert(sticker, at: 0)
        return sticker
    }

    mutating func addCloud() {
        _ = addCloud(named: "New Cloud")
    }

    @discardableResult
    mutating func addCloud(named name: String) -> StickerLibrary? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        let library = StickerLibrary(name: trimmedName, stickers: [], skin: nextCloudSkin)
        libraries.append(library)
        return library
    }

    private var nextCloudSkin: CloudSkin {
        let skins = CloudSkin.allCases
        return skins[libraries.count % skins.count]
    }

    mutating func updateLibraryAttributes(id: UUID, name: String, skin: CloudSkin) {
        guard let index = libraries.firstIndex(where: { $0.id == id }) else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            libraries[index].name = trimmedName
        }
        libraries[index].skin = skin
    }

    func librarySkin(for id: UUID?) -> CloudSkin {
        guard let id, let library = libraries.first(where: { $0.id == id }) else {
            return libraries.first?.skin ?? .sky
        }
        return library.skin
    }

    func stickers(inLibrary id: UUID?) -> [StickerItem] {
        guard let id, let library = libraries.first(where: { $0.id == id }) else {
            return libraries.first?.stickers ?? shelf
        }
        return library.stickers
    }

    func displayName(for library: StickerLibrary) -> String {
        library.name
    }
    func cloudHubSlots(maxSlots: Int = 8) -> [CloudHubSlot] {
        guard maxSlots > 0 else { return [] }
        let librarySlots = libraries.prefix(max(0, maxSlots - 1)).map(CloudHubSlot.library)
        return librarySlots + [.create]
    }

    func stickers(in libraryId: UUID?, query: String = "") -> [StickerItem] {
        let library = libraryId.flatMap { id in
            libraries.first { $0.id == id }
        } ?? libraries.first
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let stickers = library?.stickers ?? []
        return orderedStickers(stickers).filter { sticker in
            trimmedQuery.isEmpty
                || sticker.name.localizedCaseInsensitiveContains(trimmedQuery)
                || displayName(for: sticker, in: libraryId).localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    func orderedStickers(_ stickers: [StickerItem]) -> [StickerItem] {
        stickers.enumerated().sorted { lhs, rhs in
            let lhsHasName = lhs.element.hasCustomName
            let rhsHasName = rhs.element.hasCustomName
            if lhsHasName != rhsHasName {
                return lhsHasName
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    func displayName(for sticker: StickerItem, in libraryId: UUID?) -> String {
        if sticker.hasCustomName {
            return sticker.name
        }

        let stickers = (libraryId.flatMap { id in
            libraries.first { $0.id == id }?.stickers
        } ?? libraries.first?.stickers ?? [])
        let unnamed = stickers.filter { !$0.hasCustomName }
        guard let index = unnamed.firstIndex(where: { $0.id == sticker.id }) else {
            return "贴纸"
        }
        return "贴纸 \(index + 1)"
    }

    mutating func clone(_ sticker: StickerItem, in library: StickerLibrary) {
        guard let libraryIndex = libraries.firstIndex(where: { $0.id == library.id }) else { return }
        libraries[libraryIndex].stickers.insert(sticker.copy(), at: 0)
    }

    @discardableResult
    mutating func applyVisualStyle(_ style: StickerVisualStyle, in libraryId: UUID) -> Int {
        guard let library = libraries.first(where: { $0.id == libraryId }) else { return 0 }
        return applyVisualStyle(style, to: library.stickers.map(\.id))
    }

    @discardableResult
    mutating func applyVisualStyle(_ style: StickerVisualStyle, to stickerIds: [UUID]) -> Int {
        let targetIds = Set(stickerIds)
        guard !targetIds.isEmpty else { return 0 }

        let updates = Self.renderedVisualStyleUpdates(
            style: style,
            stickers: uniqueStickers(matching: targetIds)
        )
        return applyVisualStyle(style, using: updates)
    }

    @discardableResult
    mutating func applyVisualStyle(_ style: StickerVisualStyle, using updates: [StickerVisualStyleUpdate]) -> Int {
        var renderedById: [UUID: (sourceData: Data, imageData: Data)] = [:]
        updates.forEach { update in
            renderedById[update.stickerId] = (update.sourceData, update.imageData)
        }
        guard !renderedById.isEmpty else { return 0 }

        func apply(to sticker: inout StickerItem) {
            guard let rendered = renderedById[sticker.id] else { return }
            sticker.originalImageData = rendered.sourceData
            sticker.imageData = rendered.imageData
            sticker.visualStyle = style
        }

        for index in shelf.indices where renderedById.keys.contains(shelf[index].id) {
            apply(to: &shelf[index])
        }
        for libraryIndex in libraries.indices {
            for stickerIndex in libraries[libraryIndex].stickers.indices where renderedById.keys.contains(libraries[libraryIndex].stickers[stickerIndex].id) {
                apply(to: &libraries[libraryIndex].stickers[stickerIndex])
            }
        }
        for index in canvasItems.indices where renderedById.keys.contains(canvasItems[index].sticker.id) {
            apply(to: &canvasItems[index].sticker)
        }

        return updates.count
    }

    func uniqueStickers(matching targetIds: Set<UUID>) -> [StickerItem] {
        var seenIds: Set<UUID> = []
        var stickers: [StickerItem] = []

        func append(_ sticker: StickerItem) {
            guard targetIds.contains(sticker.id), !seenIds.contains(sticker.id) else { return }
            seenIds.insert(sticker.id)
            stickers.append(sticker)
        }

        shelf.forEach(append)
        libraries.flatMap(\.stickers).forEach(append)
        canvasItems.map(\.sticker).forEach(append)
        return stickers
    }

    static func renderedVisualStyleUpdates(
        style: StickerVisualStyle,
        stickers: [StickerItem]
    ) -> [StickerVisualStyleUpdate] {
        stickers.compactMap { sticker in
            guard let sourceData = sticker.originalImageData ?? sticker.imageData,
                  let imageData = StickerStyleRenderer.renderedPNGData(from: sourceData, style: style) else {
                return nil
            }
            return StickerVisualStyleUpdate(
                stickerId: sticker.id,
                sourceData: sourceData,
                imageData: imageData
            )
        }
    }

    mutating func deleteSticker(id: UUID) {
        shelf.removeAll { $0.id == id }
        canvasItems.removeAll { $0.sticker.id == id }
        for index in libraries.indices {
            libraries[index].stickers.removeAll { $0.id == id }
        }
    }

    @discardableResult
    mutating func addStickerToCanvas(_ sticker: StickerItem) -> CanvasStickerItem {
        let item = CanvasStickerItem(
            sticker: sticker,
            x: CGFloat.random(in: -70...70),
            y: CGFloat.random(in: -80...80),
            scale: 1,
            rotationDegrees: sticker.angle
        )
        canvasItems.insert(item, at: 0)
        return item
    }

    mutating func updateCanvasItem(_ item: CanvasStickerItem) {
        guard let index = canvasItems.firstIndex(where: { $0.id == item.id }) else { return }
        canvasItems[index] = item
    }

    func playgroundPhotoExportData(
        canvasSize: CGSize,
        backdropImageData: Data,
        mode: PlaygroundMode = .stack
    ) -> Data? {
        SuperStickerRenderer.render(
            items: canvasItems,
            canvasSize: canvasSize,
            backdropImageData: backdropImageData,
            mode: mode
        )?.pngData()
    }

    mutating func solidifySuperSticker(
        canvasSize: CGSize = CGSize(width: 320, height: 320),
        backdropImageData: Data? = nil,
        mode: PlaygroundMode = .stack
    ) {
        let renderedImageData = SuperStickerRenderer.render(
            items: canvasItems,
            canvasSize: canvasSize,
            backdropImageData: backdropImageData,
            mode: mode
        )?.pngData()
        superStickerCount += 1
        let item = StickerItem(
            name: "",
            symbolName: "square.stack.3d.up.fill",
            angle: -5,
            imageData: renderedImageData,
            originalImageData: renderedImageData,
            visualStyle: .whiteBorder,
            source: .playground
        )
        ensurePrimaryLibrary()
        libraries[0].stickers.insert(item, at: 0)
        shelf.insert(item, at: 0)
        canvasItems.removeAll()
    }

    @discardableResult
    mutating func updateStickerDetails(
        id: UUID,
        name: String,
        visualStyle: StickerVisualStyle? = nil
    ) -> StickerItem? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var updatedSticker: StickerItem?

        func update(_ sticker: inout StickerItem) {
            sticker.name = trimmedName
            updatedSticker = sticker
        }

        for index in shelf.indices where shelf[index].id == id {
            update(&shelf[index])
        }
        for libraryIndex in libraries.indices {
            for stickerIndex in libraries[libraryIndex].stickers.indices where libraries[libraryIndex].stickers[stickerIndex].id == id {
                update(&libraries[libraryIndex].stickers[stickerIndex])
            }
        }
        for index in canvasItems.indices where canvasItems[index].sticker.id == id {
            update(&canvasItems[index].sticker)
        }

        if let visualStyle {
            _ = applyVisualStyle(visualStyle, to: [id])
            updatedSticker = shelf.first { $0.id == id }
                ?? libraries.flatMap(\.stickers).first { $0.id == id }
                ?? canvasItems.first { $0.sticker.id == id }?.sticker
        }

        if trimmedName.isEmpty {
            moveUnnamedStickerToNumberingEnd(id: id)
        }

        return updatedSticker
    }

    private mutating func moveUnnamedStickerToNumberingEnd(id: UUID) {
        if let index = shelf.firstIndex(where: { $0.id == id }) {
            let sticker = shelf.remove(at: index)
            shelf.append(sticker)
        }

        for libraryIndex in libraries.indices {
            if let stickerIndex = libraries[libraryIndex].stickers.firstIndex(where: { $0.id == id }) {
                let sticker = libraries[libraryIndex].stickers.remove(at: stickerIndex)
                libraries[libraryIndex].stickers.append(sticker)
            }
        }
    }

    private static func renderedImageData(from data: Data?, style: StickerVisualStyle) -> Data? {
        guard let data else {
            return nil
        }
        return StickerStyleRenderer.renderedPNGData(from: data, style: style)
    }

    private mutating func ensurePrimaryLibrary() {
        if libraries.isEmpty {
            libraries.append(StickerLibrary(name: "Daily Finds", stickers: [], skin: .sky))
        }
    }

    static let seedStickers: [StickerItem] = [
        StickerItem(name: "", symbolName: "cloud.fill", angle: -2),
        StickerItem(name: "", symbolName: "camera.fill", angle: 3),
        StickerItem(name: "", symbolName: "leaf.fill", angle: -8),
        StickerItem(name: "", symbolName: "bicycle", angle: 8),
        StickerItem(name: "", symbolName: "cup.and.saucer.fill", angle: -3),
        StickerItem(name: "", symbolName: "shoeprints.fill", angle: 7),
        StickerItem(name: "", symbolName: "heart.fill", angle: -9),
        StickerItem(name: "", symbolName: "graduationcap.fill", angle: 4),
        StickerItem(name: "", symbolName: "pawprint.fill", angle: 2),
        StickerItem(name: "", symbolName: "person.fill", angle: -4),
        StickerItem(name: "", symbolName: "fork.knife.circle.fill", angle: 11),
        StickerItem(name: "", symbolName: "sparkles", angle: -11)
    ]

    static let sample = StickifyDemoState(
        shelf: Array(seedStickers.prefix(5)),
        libraries: [
            StickerLibrary(name: "Daily Finds", stickers: seedStickers, skin: .sky),
            StickerLibrary(name: "Cafe Run", stickers: Array(seedStickers[1...6]), skin: .mint),
            StickerLibrary(name: "Outfits", stickers: Array(seedStickers[5...9]), skin: .coral),
            StickerLibrary(name: "Play Mix", stickers: Array(seedStickers[0...4]), skin: .violet),
            StickerLibrary(name: "Pets", stickers: Array(seedStickers[8...10]), skin: .graphite),
            StickerLibrary(name: "Blue Things", stickers: Array(seedStickers[0...7]), skin: .sky),
            StickerLibrary(name: "Weekend", stickers: Array(seedStickers[2...11]), skin: .mint)
        ],
        canvasItems: [],
        scannedSticker: seedStickers[0]
    )
}

struct StickifyStateFileStore {
    var fileURL: URL

    static var `default`: StickifyStateFileStore {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return StickifyStateFileStore(
            fileURL: directory
                .appendingPathComponent("Stickify", isDirectory: true)
                .appendingPathComponent("stickify-state.plist")
        )
    }

    func save(_ state: StickifyDemoState) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(PersistedStickifyState(state: state))
        try data.write(to: fileURL, options: .atomic)
    }

    func load() throws -> StickifyDemoState? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try PropertyListDecoder().decode(PersistedStickifyState.self, from: data).state
    }
}

final class StickifyStateStore: ObservableObject {
    @Published var state: StickifyDemoState {
        didSet { persist() }
    }

    private let fileStore: StickifyStateFileStore

    init(fileStore: StickifyStateFileStore = .default) {
        self.fileStore = fileStore
        self.state = (try? fileStore.load()) ?? .sample
    }

    private func persist() {
        do {
            try fileStore.save(state)
        } catch {
            print("Could not persist Stickify state: \(error.localizedDescription)")
        }
    }
}

private struct PersistedStickifyState: Codable {
    var shelf: [PersistedStickerItem]
    var libraries: [PersistedStickerLibrary]
    var canvasItems: [PersistedCanvasStickerItem]
    var scannedSticker: PersistedStickerItem
    var superStickerCount: Int
    var cameraOriginalCachePreferenceRawValue: String?
    var shouldAskCleanup: Bool?

    init(state: StickifyDemoState) {
        shelf = state.shelf.map(PersistedStickerItem.init)
        libraries = state.libraries.map(PersistedStickerLibrary.init)
        canvasItems = state.canvasItems.map(PersistedCanvasStickerItem.init)
        scannedSticker = PersistedStickerItem(sticker: state.scannedSticker)
        superStickerCount = state.superStickerCount
        cameraOriginalCachePreferenceRawValue = state.cameraOriginalCachePreference.rawValue
        shouldAskCleanup = state.shouldAskCleanup
    }

    var state: StickifyDemoState {
        StickifyDemoState(
            shelf: shelf.map(\.sticker),
            libraries: libraries.map(\.library),
            canvasItems: canvasItems.map(\.canvasItem),
            scannedSticker: scannedSticker.sticker,
            superStickerCount: superStickerCount,
            cameraOriginalCachePreference: cameraOriginalCachePreference
        )
    }

    private var cameraOriginalCachePreference: CameraOriginalCachePreference {
        if let rawValue = cameraOriginalCachePreferenceRawValue,
           let preference = CameraOriginalCachePreference(rawValue: rawValue) {
            return preference
        }

        return shouldAskCleanup == false ? .deleteWithoutAsking : .askEveryTime
    }
}

private struct PersistedStickerItem: Codable {
    var id: UUID
    var name: String
    var symbolName: String
    var angle: Double
    var cloneOffset: Double
    var imageData: Data?
    var originalImageData: Data?
    var visualStyleRawValue: String
    var sourceRawValue: String

    init(sticker: StickerItem) {
        id = sticker.id
        name = sticker.name
        symbolName = sticker.symbolName
        angle = sticker.angle
        cloneOffset = Double(sticker.cloneOffset)
        imageData = sticker.imageData
        originalImageData = sticker.originalImageData
        visualStyleRawValue = sticker.visualStyle.rawValue
        sourceRawValue = sticker.source.rawValue
    }

    var sticker: StickerItem {
        StickerItem(
            id: id,
            name: name,
            symbolName: symbolName,
            angle: angle,
            cloneOffset: CGFloat(cloneOffset),
            imageData: imageData,
            originalImageData: originalImageData,
            visualStyle: StickerVisualStyle(rawValue: visualStyleRawValue) ?? .whiteBorder,
            source: StickerSource(rawValue: sourceRawValue) ?? .demo
        )
    }
}

private struct PersistedStickerLibrary: Codable {
    var id: UUID
    var name: String
    var stickers: [PersistedStickerItem]
    var skinRawValue: String?

    init(library: StickerLibrary) {
        id = library.id
        name = library.name
        stickers = library.stickers.map(PersistedStickerItem.init)
        skinRawValue = library.skin.rawValue
    }

    var library: StickerLibrary {
        StickerLibrary(id: id, name: name, stickers: stickers.map(\.sticker), skin: CloudSkin(rawValue: skinRawValue ?? "") ?? .sky)
    }
}

private struct PersistedCanvasStickerItem: Codable {
    var id: UUID
    var sticker: PersistedStickerItem
    var x: Double
    var y: Double
    var scale: Double
    var rotationDegrees: Double

    init(item: CanvasStickerItem) {
        id = item.id
        sticker = PersistedStickerItem(sticker: item.sticker)
        x = Double(item.x)
        y = Double(item.y)
        scale = Double(item.scale)
        rotationDegrees = item.rotationDegrees
    }

    var canvasItem: CanvasStickerItem {
        CanvasStickerItem(
            id: id,
            sticker: sticker.sticker,
            x: CGFloat(x),
            y: CGFloat(y),
            scale: CGFloat(scale),
            rotationDegrees: rotationDegrees
        )
    }
}

enum SuperStickerRenderer {
    private static let ciContext = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])

    static func render(
        items: [CanvasStickerItem],
        canvasSize: CGSize,
        backdropImageData: Data? = nil,
        mode: PlaygroundMode = .stack
    ) -> UIImage? {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return nil }
        guard !items.isEmpty || backdropImageData != nil else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)

        return renderer.image { context in
            drawBackdrop(backdropImageData, in: context.cgContext, canvasSize: canvasSize)

            if mode == .fusion, items.count >= 2, let fusionLayer = fusionEffectLayer(items: items, canvasSize: canvasSize) {
                let layerRect = CGRect(origin: .zero, size: canvasSize)
                fusionLayer.draw(in: layerRect, blendMode: .normal, alpha: 0.95)
                fusionLayer.draw(in: layerRect, blendMode: .plusLighter, alpha: 0.88)
            }

            for item in items.reversed() {
                draw(item, in: context.cgContext, canvasSize: canvasSize)
            }
        }
    }

    static func fusionEffectLayer(items: [CanvasStickerItem], canvasSize: CGSize) -> UIImage? {
        guard items.count >= 2,
              let stickerLayer = stickerLayer(items: items, canvasSize: canvasSize),
              let input = CIImage(image: stickerLayer) else {
            return nil
        }

        let clamp = CIFilter.affineClamp()
        clamp.inputImage = input
        clamp.transform = .identity

        let expandedInput = expandedAlphaImage(from: clamp.outputImage) ?? clamp.outputImage

        let blur = CIFilter.gaussianBlur()
        blur.inputImage = expandedInput
        blur.radius = 10

        let color = CIFilter.colorControls()
        color.inputImage = blur.outputImage?.cropped(to: input.extent)
        color.saturation = 2.4
        color.brightness = 0.1
        color.contrast = 1.5

        let alphaBoost = CIFilter.colorMatrix()
        alphaBoost.inputImage = color.outputImage
        alphaBoost.rVector = CIVector(x: 2.9, y: 0, z: 0, w: 0)
        alphaBoost.gVector = CIVector(x: 0, y: 0.42, z: 0, w: 0)
        alphaBoost.bVector = CIVector(x: 0, y: 0, z: 2.9, w: 0)
        alphaBoost.aVector = CIVector(x: 0, y: 0, z: 0, w: 8)
        alphaBoost.biasVector = CIVector(x: 0.08, y: 0, z: 0.1, w: 0)

        guard let output = alphaBoost.outputImage?.cropped(to: input.extent),
              let cgImage = ciContext.createCGImage(output, from: input.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage, scale: stickerLayer.scale, orientation: .up)
    }

    private static func expandedAlphaImage(from image: CIImage?) -> CIImage? {
        guard let image,
              let filter = CIFilter(name: "CIMorphologyMaximum") else {
            return image
        }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(18, forKey: kCIInputRadiusKey)
        return filter.outputImage
    }

    private static func stickerLayer(items: [CanvasStickerItem], canvasSize: CGSize) -> UIImage? {
        guard !items.isEmpty, canvasSize.width > 0, canvasSize.height > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)

        return renderer.image { context in
            for item in items.reversed() {
                draw(item, in: context.cgContext, canvasSize: canvasSize)
            }
        }
    }

    private static func drawBackdrop(_ data: Data?, in context: CGContext, canvasSize: CGSize) {
        guard let data, let image = UIImage(data: data) else { return }

        UIColor.white.setFill()
        context.fill(CGRect(origin: .zero, size: canvasSize))

        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        let scale = min(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)
        let fittedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let rect = CGRect(
            x: (canvasSize.width - fittedSize.width) / 2,
            y: (canvasSize.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
        image.draw(in: rect)
    }

    private static func draw(_ item: CanvasStickerItem, in context: CGContext, canvasSize: CGSize) {
        let stickerSize: CGFloat = 86
        let center = CGPoint(
            x: canvasSize.width / 2 + item.x,
            y: canvasSize.height / 2 + item.y
        )
        let drawSize = CGSize(width: stickerSize, height: stickerSize)
        let drawRect = CGRect(
            x: -drawSize.width / 2,
            y: -drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )

        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: CGFloat(item.rotationDegrees * .pi / 180))
        context.scaleBy(x: item.scale, y: item.scale)

        if let data = item.sticker.imageData, let image = UIImage(data: data) {
            image.draw(in: drawRect.insetBy(dx: stickerSize * 0.04, dy: stickerSize * 0.04))
        } else {
            drawSymbolSticker(item.sticker, in: drawRect)
        }

        context.restoreGState()
    }

    private static func drawSymbolSticker(_ sticker: StickerItem, in rect: CGRect) {
        let basePath = UIBezierPath(roundedRect: rect, cornerRadius: rect.width * 0.31)
        UIColor.white.setFill()
        basePath.fill()

        let innerRect = rect.insetBy(dx: rect.width * 0.11, dy: rect.height * 0.11)
        let innerPath = UIBezierPath(roundedRect: innerRect, cornerRadius: rect.width * 0.28)
        UIColor(sticker.color).withAlphaComponent(0.18).setFill()
        innerPath.fill()

        guard let symbol = UIImage(systemName: sticker.symbolName) else { return }
        let symbolSize = rect.width * 0.38
        let symbolRect = CGRect(
            x: rect.midX - symbolSize / 2,
            y: rect.midY - symbolSize / 2,
            width: symbolSize,
            height: symbolSize
        )
        UIColor(sticker.color).setFill()
        symbol.withTintColor(UIColor(sticker.color), renderingMode: .alwaysOriginal).draw(in: symbolRect)
    }
}

