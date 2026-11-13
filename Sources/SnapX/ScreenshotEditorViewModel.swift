@preconcurrency import AppKit
import SwiftUI

enum ToastKind {
    case success
    case warning
}

struct ToastState: Equatable {
    let message: String
    let kind: ToastKind
}

/// One undo step: annotation history plus the image and crop frame so that
/// recropping is undoable too.
struct EditorSnapshot {
    let image: NSImage
    let annotations: [ScreenshotEditorAnnotation]
    let cropRect: CGRect?
}

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
                undoSnapshots.append(EditorSnapshot(image: image, annotations: oldValue, cropRect: editorCropRect))
                redoSnapshots.removeAll()
            }
        }
    }
    @Published private var undoSnapshots: [EditorSnapshot] = []
    @Published private var redoSnapshots: [EditorSnapshot] = []
    private var isApplyingHistory = false
    // Mirrored from the root view so undo snapshots can restore the crop frame.
    var editorCropRect: CGRect = .zero
    @Published var restoredCropRect: CGRect?
    @Published private(set) var ocrScan: OCRScanTimeline?
    var isExtractingText: Bool { ocrScan != nil }
    @Published var toast: ToastState?
    @Published var hasActiveTextDraft = false
    @Published var textDraftDiscardRequest = false
    @Published var colorPaletteDismissRequest = false
    // Mirror of the root view's palette state so the window-level Esc monitor
    // can dismiss the palette instead of closing the editor.
    var isColorPalettePresented = false

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
        redoSnapshots.append(EditorSnapshot(image: image, annotations: annotations, cropRect: editorCropRect))
        restore(previous)
    }

    func redoLastAnnotation() {
        guard let next = redoSnapshots.popLast() else { return }
        undoSnapshots.append(EditorSnapshot(image: image, annotations: annotations, cropRect: editorCropRect))
        restore(next)
    }

    private func restore(_ snapshot: EditorSnapshot) {
        isApplyingHistory = true
        defer { isApplyingHistory = false }
        if snapshot.image !== image {
            image = snapshot.image
            cancelTextExtraction()
            previewTask?.cancel()
            previewTask = nil
            previewGeneration += 1
            pixelatedPreviewImage = nil
            if activeTool == .mosaic { generatePixelatedPreview(for: image) }
        }
        annotations = snapshot.annotations
        if let rect = snapshot.cropRect { restoredCropRect = rect }
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

    func recrop(newRect: CGRect, oldRect: CGRect? = nil) {
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
        undoSnapshots.append(EditorSnapshot(image: image, annotations: annotations,
            cropRect: oldRect ?? editorCropRect))
        redoSnapshots.removeAll()
        cancelTextExtraction()
        image = newImage
        previewTask?.cancel()
        previewTask = nil
        previewGeneration += 1
        pixelatedPreviewImage = nil
        // Keep annotations by re-expressing them in the new crop's coordinate
        // space; marks that fall entirely outside are dropped.
        if let oldRect {
            let offset = CGSize(width: oldRect.minX - newRect.minX, height: oldRect.minY - newRect.minY)
            let newBounds = CGRect(origin: .zero, size: newRect.size)
            isApplyingHistory = true
            annotations = annotations
                .map { $0.translated(by: offset) }
                .filter { $0.canvasBounds.intersects(newBounds) }
            isApplyingHistory = false
        } else {
            isApplyingHistory = true
            annotations.removeAll()
            isApplyingHistory = false
        }
        if activeTool == .mosaic { generatePixelatedPreview(for: newImage) }
    }

    func showToast(_ message: String, kind: ToastKind = .success, duration: TimeInterval = 1.8) {
        toastDismissTask?.cancel()
        toast = ToastState(message: message, kind: kind)

        toastDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, duration) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.toast = nil
            }
        }
    }
}
