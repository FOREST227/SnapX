@preconcurrency import AppKit
import SwiftUI

@MainActor
final class ScreenshotEditorViewModel: ObservableObject {
    @Published var image: NSImage
    @Published var pixelatedPreviewImage: NSImage?

    let cropInfo: ScreenshotEditorCropInfo?

    @Published var activeTool: ScreenshotEditorTool = .rectangle {
        didSet {
            if activeTool == .mosaic, pixelatedPreviewImage == nil, previewTask == nil {
                generatePixelatedPreview(for: image)
            }
        }
    }
    @Published var selectedColor: ScreenshotAnnotationColor = .red
    @Published var highlightOpacity: Double = 0.35
    @Published var highlightBrushSize: Double = 24
    @Published var mosaicBrushSize: Double = 28
    @Published var textFontSize: CGFloat = 24
    @Published var textIsBold: Bool = false
    @Published var textIsItalic: Bool = false
    @Published var textIsUnderline: Bool = false
    @Published var annotations: [ScreenshotEditorAnnotation] = [] {
        didSet {
            if !isApplyingHistory {
                undoSnapshots.append(oldValue)
                redoSnapshots.removeAll()
            }
        }
    }
    @Published private var undoSnapshots: [[ScreenshotEditorAnnotation]] = []
    @Published private var redoSnapshots: [[ScreenshotEditorAnnotation]] = []
    private var isApplyingHistory = false
    @Published private(set) var ocrScan: OCRScanTimeline?
    var isExtractingText: Bool { ocrScan != nil }
    @Published var toastMessage: String?
    @Published var hasActiveTextDraft = false
    @Published var textDraftDiscardRequest = false

    private var toastDismissTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var previewGeneration = 0
    private let previewGenerator: @Sendable (NSImage) -> NSImage?

    init(image: NSImage, cropInfo: ScreenshotEditorCropInfo? = nil,
         previewGenerator: @escaping @Sendable (NSImage) -> NSImage? = { ScreenshotEditorRenderer.makePixelatedPreviewImage(for: $0) }) {
        self.previewGenerator = previewGenerator
        self.image = image
        self.cropInfo = cropInfo
        pixelatedPreviewImage = nil
    }

    private func generatePixelatedPreview(for image: NSImage) {
        let generator = previewGenerator
        let generation = previewGeneration
        previewTask = Task.detached(priority: .userInitiated) { @Sendable [weak self] in
            guard !Task.isCancelled else { return }
            let pixelated = generator(image)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.previewGeneration == generation else { return }
                self.pixelatedPreviewImage = pixelated
                self.previewTask = nil
            }
        }
    }

    var canUndo: Bool {
        !undoSnapshots.isEmpty
    }

    var canRedo: Bool {
        !redoSnapshots.isEmpty
    }

    var canAdjustCrop: Bool {
        cropInfo != nil
    }

    func addAnnotation(_ annotation: ScreenshotEditorAnnotation) {
        annotations.append(annotation)
    }

    func makeHighlight(points: [CGPoint]) -> HighlightAnnotation {
        HighlightAnnotation(points: points, color: selectedColor,
            opacity: CGFloat(highlightOpacity.isFinite ? min(max(highlightOpacity, 0), 1) : 0.35),
            brushSize: CGFloat(highlightBrushSize.isFinite ? min(max(highlightBrushSize, 8), 64) : 24))
    }

    func addHighlight(points: [CGPoint]) { addHighlight(makeHighlight(points: points)) }

    func addHighlight(_ stroke: HighlightAnnotation) {
        guard !stroke.points.isEmpty else { return }
        addAnnotation(.highlight(stroke))
    }

    func addMosaic(points: [CGPoint]) {
        guard !points.isEmpty else { return }
        addAnnotation(.mosaic(MosaicAnnotation(points: points,
            brushSize: CGFloat(min(max(mosaicBrushSize, 8), 100)))))
    }

    func undoLastAnnotation() {
        guard let previous = undoSnapshots.popLast() else { return }
        isApplyingHistory = true
        defer { isApplyingHistory = false }
        redoSnapshots.append(annotations)
        annotations = previous
    }

    func redoLastAnnotation() {
        guard let next = redoSnapshots.popLast() else { return }
        isApplyingHistory = true
        defer { isApplyingHistory = false }
        undoSnapshots.append(annotations)
        annotations = next
    }

    func renderedImage() -> NSImage {
        ScreenshotEditorRenderer.render(image: image, annotations: annotations)
    }

    func beginTextExtraction() -> UUID {
        let scan = OCRScanTimeline(startedAt: ProcessInfo.processInfo.systemUptime)
        ocrScan = scan
        return scan.id
    }

    func finishTextExtractionScan(id: UUID, reduceMotion: Bool) async throws -> Bool {
        guard let scan = ocrScan, scan.id == id else { return false }
        if !reduceMotion {
            let remaining = max(0, scan.startedAt + OCRScanTimeline.duration - ProcessInfo.processInfo.systemUptime)
            try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
        }
        try Task.checkCancellation()
        guard ocrScan?.id == id else { return false }
        ocrScan = nil
        return true
    }

    func cancelTextExtraction() { ocrScan = nil }

    func recrop(newRect: CGRect) {
        guard let cropInfo else { return }
        let sf = cropInfo.scaleFactor
        let pixelRect = CGRect(
            x: newRect.minX * sf,
            y: newRect.minY * sf,
            width: newRect.width * sf,
            height: newRect.height * sf
        ).integral

        guard let fullCG = cropInfo.fullScreenImage.cgImageRepresentation,
              let croppedCG = fullCG.cropping(to: pixelRect) else { return }

        let newImage = NSImage(cgImage: croppedCG, size: newRect.size)
        cancelTextExtraction()
        image = newImage
        previewTask?.cancel()
        previewTask = nil
        previewGeneration += 1
        pixelatedPreviewImage = nil
        isApplyingHistory = true
        annotations.removeAll()
        isApplyingHistory = false
        undoSnapshots.removeAll()
        redoSnapshots.removeAll()
        if activeTool == .mosaic { generatePixelatedPreview(for: newImage) }
    }

    func showToast(_ message: String, duration: TimeInterval = 1.8) {
        toastDismissTask?.cancel()
        toastMessage = message

        toastDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, duration) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.toastMessage = nil
            }
        }
    }
}
