import AppKit
import Carbon.HIToolbox
import Foundation
import QuartzCore

@MainActor
final class SelectionOverlayWindowController: NSWindowController {
    let screen: NSScreen

    init(
        screen: NSScreen,
        mode: CaptureSelectionMode,
        hotKeyHint: String,
        frozenImage: CGImage?,
        frozenWindowInfo: [[String: Any]]?,
        desktopTopEdge: CGFloat? = nil,
        isEdgeSnappingEnabled: Bool = false,
        edgeSnappingRange: CGFloat = CGFloat(EdgeSnapRange.defaultValue),
        captureHandler: @escaping (ScreenshotCaptureRequest) -> Void,
        cancelHandler: @escaping () -> Void
    ) {
        self.screen = screen

        let hasFrozenBackdrop = frozenImage != nil
        let window = SelectionOverlayWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )

        window.backgroundColor = hasFrozenBackdrop ? .black : .clear
        window.isOpaque = hasFrozenBackdrop
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isReleasedWhenClosed = false
        window.setFrame(screen.frame, display: false)

        let contentView = SelectionOverlayCanvasView(
            frame: CGRect(origin: .zero, size: screen.frame.size),
            screen: screen,
            mode: mode,
            hotKeyHint: hotKeyHint,
            frozenImage: frozenImage,
            frozenWindowInfo: frozenWindowInfo,
            desktopTopEdge: desktopTopEdge,
            isEdgeSnappingEnabled: isEdgeSnappingEnabled,
            edgeSnappingRange: edgeSnappingRange,
            captureHandler: captureHandler,
            cancelHandler: cancelHandler
        )
        window.contentView = contentView

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func freeze(_ image: CGImage) {
        window?.isOpaque = true
        window?.backgroundColor = .black
        (window?.contentView as? SelectionOverlayCanvasView)?.freeze(image)
    }

    func contains(globalRect: CGRect) -> Bool {
        screen.frame.intersects(globalRect)
    }

    override func close() {
        (window?.contentView as? SelectionOverlayCanvasView)?.tearDown()
        super.close()
    }

    func takeWindowForTransition() -> NSWindow? {
        (window?.contentView as? SelectionOverlayCanvasView)?.stopEdgeAnalysis()
        let retainedWindow = window
        window = nil
        return retainedWindow
    }
}

private final class SelectionOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private struct HighlightedCaptureTarget: Equatable {
    let highlightRect: CGRect
    let contentSize: CGSize
    let displayName: String
    let captureRequest: ScreenshotCaptureRequest
}

private final class PassthroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class PassthroughChromeView: NSView {
    let chromeRootLayer = CALayer()
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        chromeRootLayer.isGeometryFlipped = true
        chromeRootLayer.frame = CGRect(origin: .zero, size: frameRect.size)
        layer = chromeRootLayer
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        chromeRootLayer.frame = CGRect(origin: .zero, size: newSize)
        CATransaction.commit()
    }
}

private final class FloatingPillLabelView: NSView {
    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private let textField: NSTextField
    private let padding = CGSize(width: 12, height: 8)
    private var lastText: String?
    private var cachedContentSize: CGSize = .zero

    override init(frame frameRect: NSRect) {
        let field = NSTextField(labelWithString: "")
        field.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
        field.textColor = .white
        field.lineBreakMode = .byClipping
        field.maximumNumberOfLines = 1
        field.isBezeled = false
        field.drawsBackground = false
        field.isEditable = false
        field.isSelectable = false
        self.textField = field

        super.init(frame: frameRect)
        wantsLayer = true
        needsDisplay = true
        addSubview(field)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateLayer() {
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
    }

    func update(text: String, near rect: CGRect, in containerBounds: CGRect) {
        if lastText != text {
            lastText = text
            textField.stringValue = text
            textField.sizeToFit()
            cachedContentSize = textField.frame.size
            textField.frame = CGRect(
                x: padding.width,
                y: padding.height,
                width: cachedContentSize.width,
                height: cachedContentSize.height
            )
        }

        let width = cachedContentSize.width + padding.width * 2
        let height = cachedContentSize.height + padding.height * 2
        let nextFrame = CGRect(
            x: min(max(rect.minX, 14), max(containerBounds.width - width - 14, 14)),
            y: max(rect.minY - height - 10, 14),
            width: width,
            height: height
        )
        if frame != nextFrame {
            frame = nextFrame
        }
        if isHidden {
            isHidden = false
        }
    }
}

private final class OverlayInstructionView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private let titleField: NSTextField
    private let captionField: NSTextField

    init(title: String, caption: String) {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 30, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.alignment = .center
        titleLabel.sizeToFit()

        let captionLabel = NSTextField(labelWithString: caption)
        captionLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        captionLabel.textColor = NSColor.white.withAlphaComponent(0.78)
        captionLabel.alignment = .center
        captionLabel.sizeToFit()

        self.titleField = titleLabel
        self.captionField = captionLabel

        let width = max(titleLabel.frame.width, captionLabel.frame.width)
        let height = titleLabel.frame.height + 12 + captionLabel.frame.height
        super.init(frame: CGRect(x: 0, y: 0, width: width, height: height))

        titleLabel.frame.origin = CGPoint(x: (width - titleLabel.frame.width) / 2, y: 0)
        captionLabel.frame.origin = CGPoint(x: (width - captionLabel.frame.width) / 2, y: titleLabel.frame.height + 12)
        addSubview(titleLabel)
        addSubview(captionLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func center(in containerBounds: CGRect) {
        let origin = CGPoint(
            x: (containerBounds.width - frame.width) / 2,
            y: (containerBounds.height - frame.height) / 2
        )
        if frame.origin != origin {
            frame.origin = origin
        }
    }
}

final class SelectionOverlayCanvasView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private static var cachedDockDisplayName: String?

    private let dragActivationDistance: CGFloat = 4
    private let screen: NSScreen
    private let mode: CaptureSelectionMode
    private let hotKeyHint: String
    private let isEdgeSnappingEnabled: Bool
    private let edgeSnappingRange: CGFloat
    private let edgeAnalysis = EdgeSnapAnalysis()
    private var bypassSnapping = false
    private var pointerPoint: CGPoint?
    private var startingAnchor: SnapAnchor?
    private var confirmedSnapResult: EdgeSnapResult?
    private var lastRenderedAnchorPreview: CGPoint?
    private var frozenImage: CGImage?
    private var frozenWindowInfo: [[String: Any]]?
    private let hasFrozenWindowSnapshot: Bool
    private let captureHandler: (ScreenshotCaptureRequest) -> Void
    private let cancelHandler: () -> Void

    private let displayBounds: CGRect
    private let currentProcessID = ProcessInfo.processInfo.processIdentifier
    private var trackingArea: NSTrackingArea?
    private var dragStartPoint: CGPoint?
    private var dragCurrentPoint: CGPoint?
    private var isAreaSelectionActive = false
    private var highlightedTarget: HighlightedCaptureTarget?
    private var isPointerInsideScreen = false
    private var preparedWindowTargets: [HighlightedCaptureTarget]?
    private var windowInfoCacheTime: CFTimeInterval = 0
    private let windowInfoCacheInterval: CFTimeInterval = 0.2
    private let desktopTopEdge: CGFloat

    // GPU-composited subviews and zero-backing-store solid CALayers eliminate full-screen CPU redraws.
    private let backdropView: PassthroughImageView
    private let chromeView: PassthroughChromeView
    private let dimTopLayer = CALayer()
    private let dimBottomLayer = CALayer()
    private let dimLeftLayer = CALayer()
    private let dimRightLayer = CALayer()
    private let outlineLayer = CALayer()
    private let snappedEdgeLayers: [CALayer] = (0..<4).map { _ in CALayer() }
    private let anchorHLineLayer = CALayer()
    private let anchorVLineLayer = CALayer()
    private let anchorDotLayer = CALayer()
    private let floatingLabelView: FloatingPillLabelView
    private var instructionView: OverlayInstructionView?

    init(
        frame frameRect: CGRect,
        screen: NSScreen,
        mode: CaptureSelectionMode,
        hotKeyHint: String,
        frozenImage: CGImage?,
        frozenWindowInfo: [[String: Any]]?,
        desktopTopEdge: CGFloat? = nil,
        isEdgeSnappingEnabled: Bool = false,
        edgeSnappingRange: CGFloat = CGFloat(EdgeSnapRange.defaultValue),
        captureHandler: @escaping (ScreenshotCaptureRequest) -> Void,
        cancelHandler: @escaping () -> Void
    ) {
        self.screen = screen
        self.mode = mode
        self.hotKeyHint = hotKeyHint
        self.isEdgeSnappingEnabled = isEdgeSnappingEnabled && mode == .framed
        self.edgeSnappingRange = CGFloat(EdgeSnapRange.normalized(Double(edgeSnappingRange)))
        self.frozenImage = frozenImage
        self.frozenWindowInfo = frozenWindowInfo
        self.hasFrozenWindowSnapshot = frozenWindowInfo != nil
        self.captureHandler = captureHandler
        self.cancelHandler = cancelHandler
        self.displayBounds = CGDisplayBounds(screen.displayID)
        self.desktopTopEdge = desktopTopEdge ?? NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY

        let backdrop = PassthroughImageView(frame: CGRect(origin: .zero, size: frameRect.size))
        backdrop.autoresizingMask = [.width, .height]
        backdrop.imageScaling = .scaleAxesIndependently
        backdrop.imageAlignment = .alignCenter
        if let frozenImage {
            backdrop.image = NSImage(cgImage: frozenImage, size: frameRect.size)
            backdrop.isHidden = false
        } else {
            backdrop.isHidden = true
        }
        self.backdropView = backdrop

        let chrome = PassthroughChromeView(frame: CGRect(origin: .zero, size: frameRect.size))
        chrome.autoresizingMask = [.width, .height]
        self.chromeView = chrome

        let floatingLabel = FloatingPillLabelView(frame: .zero)
        floatingLabel.isHidden = true
        self.floatingLabelView = floatingLabel

        super.init(frame: frameRect)
        wantsLayer = true
        configureChromeLayers()

        addSubview(backdropView)
        addSubview(chromeView)
        addSubview(floatingLabelView)

        edgeAnalysis.onUpdate = { [weak self] in
            self?.updateStartingAnchor()
            self?.updateChrome()
        }

        updateChrome()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureChromeLayers() {
        let rootLayer = chromeView.chromeRootLayer

        let dimColor = NSColor.black.withAlphaComponent(SelectionChromeStyle.dimOpacity).cgColor
        for layer in [dimTopLayer, dimBottomLayer, dimLeftLayer, dimRightLayer] {
            layer.backgroundColor = dimColor
            layer.isHidden = true
            rootLayer.addSublayer(layer)
        }

        outlineLayer.backgroundColor = nil
        outlineLayer.isHidden = true
        rootLayer.addSublayer(outlineLayer)

        let snappedColor = SelectionChromeStyle.snappedEdgeNSColor.cgColor
        for layer in snappedEdgeLayers {
            layer.backgroundColor = snappedColor
            layer.isHidden = true
            rootLayer.addSublayer(layer)
        }

        for layer in [anchorHLineLayer, anchorVLineLayer, anchorDotLayer] {
            layer.isHidden = true
            rootLayer.addSublayer(layer)
        }
        anchorDotLayer.cornerRadius = 4
        anchorDotLayer.borderWidth = 1
        anchorDotLayer.borderColor = NSColor.white.cgColor
    }

    func stopEdgeAnalysis() { edgeAnalysis.stop() }

    func tearDown() {
        edgeAnalysis.stop()
        frozenImage = nil
        frozenWindowInfo = nil
        preparedWindowTargets = nil
        backdropView.image = nil
    }

    func freeze(_ image: CGImage) {
        edgeAnalysis.stop()
        frozenImage = image
        backdropView.image = NSImage(cgImage: image, size: bounds.size)
        backdropView.isHidden = false
        updateChrome()
        CATransaction.flush()
    }

    override func layout() {
        super.layout()
        updateChrome()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateChrome()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        if window == nil { edgeAnalysis.stop() }
        else if isEdgeSnappingEnabled {
            if let image = frozenImage {
                edgeAnalysis.start(size: bounds.size, continuous: false, image: { image })
            } else { startLiveEdgeAnalysis() }
        }
        refreshHoverState()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseDown(with event: NSEvent) {
        let point = clampedPoint(for: event)

        switch mode {
        case .framed:
            isPointerInsideScreen = true
            confirmedSnapResult = nil
            bypassSnapping = event.modifierFlags.contains(.option)
            dragStartPoint = point
            dragCurrentPoint = point
            startingAnchor = nil
            updateStartingAnchor()
            isAreaSelectionActive = false
            updateHighlightedTarget(at: point, forceRedraw: true)

        case .display:
            isPointerInsideScreen = true
            updateChrome()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard mode == .framed else { return }

        let point = clampedPoint(for: event)

        guard let dragStartPoint else { return }
        dragCurrentPoint = point
        bypassSnapping = event.modifierFlags.contains(.option)
        if !isAreaSelectionActive,
           dragDistance(from: dragStartPoint, to: point) >= dragActivationDistance {
            isAreaSelectionActive = true
        }
        updateChrome()
    }

    override func mouseMoved(with event: NSEvent) {
        let nextBypass = event.modifierFlags.contains(.option)
        let bypassChanged = bypassSnapping != nextBypass
        bypassSnapping = nextBypass
        let point = clampedPoint(for: event)

        switch mode {
        case .framed:
            let entered = !isPointerInsideScreen
            if entered { isPointerInsideScreen = true }
            updateHighlightedTarget(at: point, forceRedraw: entered || bypassChanged)

        case .display:
            if !isPointerInsideScreen {
                isPointerInsideScreen = true
                updateChrome()
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        let point = clampedPoint(for: event)

        switch mode {
        case .framed:
            bypassSnapping = event.modifierFlags.contains(.option)
            dragCurrentPoint = point
            let shouldTreatAsAreaSelection: Bool
            if let dragStartPoint {
                shouldTreatAsAreaSelection =
                    isAreaSelectionActive || dragDistance(from: dragStartPoint, to: point) >= dragActivationDistance
            } else {
                shouldTreatAsAreaSelection = isAreaSelectionActive
            }

            if shouldTreatAsAreaSelection, !isAreaSelectionActive {
                isAreaSelectionActive = true
            }

            let resolvedSnap = snapResult
            let rect = resolvedSnap?.rect

            defer {
                dragStartPoint = nil
                dragCurrentPoint = nil
                isAreaSelectionActive = false
                startingAnchor = nil
                updateChrome()
            }

            if shouldTreatAsAreaSelection {
                guard let rect, rect.width >= 8, rect.height >= 8 else {
                    NSSound.beep()
                    return
                }

                confirmAreaSelection(rect, edges: resolvedSnap?.edges ?? [])
                return
            }

            updateHighlightedTarget(at: point)
            guard let highlightedTarget else {
                NSSound.beep()
                return
            }

            captureHandler(highlightedTarget.captureRequest)

        case .display:
            isPointerInsideScreen = true
            guard let displaySelection = makeFullScreenSelection() else {
                cancelHandler()
                return
            }

            captureHandler(.display(displaySelection))
        }
    }

    override func flagsChanged(with event: NSEvent) {
        let nextBypass = event.modifierFlags.contains(.option)
        guard nextBypass != bypassSnapping else { return }
        bypassSnapping = nextBypass
        updateChrome()
    }

    private func startLiveEdgeAnalysis() {
        guard let window else { return }
        let windowID = CGWindowID(window.windowNumber)
        let captureBounds = displayBounds
        // Read below our overlay, so selection borders and dimming never become snap candidates.
        // These analysis frames are separate from the final confirmation capture.
        edgeAnalysis.start(size: bounds.size, continuous: true) {
            CGWindowListCreateImage(captureBounds, .optionOnScreenBelowWindow, windowID, .bestResolution)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            cancelHandler()
            return
        }

        super.keyDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        cancelHandler()
    }

    override func mouseEntered(with event: NSEvent) {
        switch mode {
        case .framed:
            isPointerInsideScreen = true
            updateHighlightedTarget(at: clampedPoint(for: event), forceRedraw: true)

        case .display:
            isPointerInsideScreen = true
            updateChrome()
        }
    }

    override func mouseExited(with event: NSEvent) {
        switch mode {
        case .framed:
            isPointerInsideScreen = false
            highlightedTarget = nil
            NSCursor.arrow.set()
            updateChrome()

        case .display:
            isPointerInsideScreen = false
            updateChrome()
        }
    }

    private func updateChrome() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let activeSnapResult = mode == .framed ? snapResult : nil
        let areaRect = activeSnapResult?.rect
        let highlightRect = areaRect == nil ? highlightedTargetRect : nil

        let cutoutRect: CGRect?
        switch mode {
        case .framed:
            cutoutRect = areaRect ?? highlightRect
        case .display:
            cutoutRect = isPointerInsideScreen ? bounds : nil
        }

        updateDimLayers(cutoutRect: cutoutRect)

        var frameAccentCGColor: CGColor?
        effectiveAppearance.performAsCurrentDrawingAppearance {
            frameAccentCGColor = SelectionChromeStyle.frameNSColor.cgColor
        }
        let accentCGColor = frameAccentCGColor ?? NSColor.systemBlue.cgColor

        switch mode {
        case .framed:
            if let areaRect {
                updateOutlineLayer(
                    rect: areaRect,
                    cornerRadius: SelectionChromeStyle.frameCornerRadius,
                    lineWidth: SelectionChromeStyle.frameLineWidth,
                    color: accentCGColor
                )
                updateSnappedEdgeLayers(for: activeSnapResult)
                floatingLabelView.update(
                    text: "\(Int(areaRect.width)) × \(Int(areaRect.height))" + snappingHint(for: activeSnapResult),
                    near: areaRect,
                    in: bounds
                )
                setInstructionVisible(false)
            } else if let highlightRect, let highlightedTarget {
                updateOutlineLayer(
                    rect: highlightRect,
                    cornerRadius: 10,
                    lineWidth: 2,
                    color: NSColor.white.withAlphaComponent(0.92).cgColor
                )
                hideSnappedEdgeLayers()
                floatingLabelView.update(
                    text: "\(highlightedTarget.displayName) • \(Int(highlightedTarget.contentSize.width)) × \(Int(highlightedTarget.contentSize.height))",
                    near: highlightRect,
                    in: bounds
                )
                setInstructionVisible(false)
            } else {
                outlineLayer.isHidden = true
                hideSnappedEdgeLayers()
                floatingLabelView.isHidden = true
                setInstructionVisible(true)
            }

        case .display:
            hideSnappedEdgeLayers()
            if isPointerInsideScreen {
                let displayHighlightRect = bounds.insetBy(dx: 8, dy: 8)
                updateOutlineLayer(
                    rect: displayHighlightRect,
                    cornerRadius: 10,
                    lineWidth: 2,
                    color: NSColor.white.withAlphaComponent(0.92).cgColor
                )
                floatingLabelView.update(
                    text: "整个屏幕 • \(Int(bounds.width)) × \(Int(bounds.height))",
                    near: displayHighlightRect,
                    in: bounds
                )
                setInstructionVisible(false)
            } else {
                outlineLayer.isHidden = true
                floatingLabelView.isHidden = true
                setInstructionVisible(true)
            }
        }

        if mode == .framed {
            updateAnchorPreviewLayers(using: activeSnapResult, accentColor: accentCGColor)
        } else {
            hideAnchorPreviewLayers()
        }
    }

    private func updateDimLayers(cutoutRect: CGRect?) {
        let width = bounds.width
        let height = bounds.height

        guard let cutoutRect else {
            dimTopLayer.frame = bounds
            dimTopLayer.isHidden = false
            dimBottomLayer.isHidden = true
            dimLeftLayer.isHidden = true
            dimRightLayer.isHidden = true
            return
        }

        let r = cutoutRect.intersection(bounds)
        if r.isNull || r.isEmpty {
            dimTopLayer.frame = bounds
            dimTopLayer.isHidden = false
            dimBottomLayer.isHidden = true
            dimLeftLayer.isHidden = true
            dimRightLayer.isHidden = true
            return
        }

        let topHeight = r.minY
        if topHeight > 0 {
            dimTopLayer.frame = CGRect(x: 0, y: 0, width: width, height: topHeight)
            dimTopLayer.isHidden = false
        } else {
            dimTopLayer.isHidden = true
        }

        let bottomHeight = height - r.maxY
        if bottomHeight > 0 {
            dimBottomLayer.frame = CGRect(x: 0, y: r.maxY, width: width, height: bottomHeight)
            dimBottomLayer.isHidden = false
        } else {
            dimBottomLayer.isHidden = true
        }

        let leftWidth = r.minX
        if leftWidth > 0 && r.height > 0 {
            dimLeftLayer.frame = CGRect(x: 0, y: r.minY, width: leftWidth, height: r.height)
            dimLeftLayer.isHidden = false
        } else {
            dimLeftLayer.isHidden = true
        }

        let rightWidth = width - r.maxX
        if rightWidth > 0 && r.height > 0 {
            dimRightLayer.frame = CGRect(x: r.maxX, y: r.minY, width: rightWidth, height: r.height)
            dimRightLayer.isHidden = false
        } else {
            dimRightLayer.isHidden = true
        }
    }

    private func updateOutlineLayer(rect: CGRect, cornerRadius: CGFloat, lineWidth: CGFloat, color: CGColor) {
        let half = lineWidth / 2
        outlineLayer.frame = rect.insetBy(dx: -half, dy: -half)
        outlineLayer.borderWidth = lineWidth
        outlineLayer.cornerRadius = cornerRadius + half
        outlineLayer.borderColor = color
        outlineLayer.isHidden = false
    }

    private func updateSnappedEdgeLayers(for result: EdgeSnapResult?) {
        guard let result, !result.edges.isEmpty else {
            hideSnappedEdgeLayers()
            return
        }

        let thickness: CGFloat = 2
        let half = thickness / 2
        for (index, layer) in snappedEdgeLayers.enumerated() {
            guard index < result.edges.count else {
                layer.isHidden = true
                continue
            }
            let edge = result.edges[index]
            if edge.axis == .horizontal {
                let y = abs(edge.position - result.rect.minY) < abs(edge.position - result.rect.maxY)
                    ? result.rect.minY : result.rect.maxY
                layer.frame = CGRect(x: result.rect.minX, y: y - half, width: result.rect.width, height: thickness)
            } else {
                let x = abs(edge.position - result.rect.minX) < abs(edge.position - result.rect.maxX)
                    ? result.rect.minX : result.rect.maxX
                layer.frame = CGRect(x: x - half, y: result.rect.minY, width: thickness, height: result.rect.height)
            }
            layer.isHidden = false
        }
    }

    private func hideSnappedEdgeLayers() {
        for layer in snappedEdgeLayers where !layer.isHidden {
            layer.isHidden = true
        }
    }

    private func updateAnchorPreviewLayers(using activeSnapResult: EdgeSnapResult?, accentColor: CGColor) {
        let point = confirmedSnapResult == nil ? resolveAnchorPreviewPoint(using: activeSnapResult) : nil
        lastRenderedAnchorPreview = point

        guard let point else {
            hideAnchorPreviewLayers()
            return
        }

        anchorHLineLayer.backgroundColor = accentColor
        anchorVLineLayer.backgroundColor = accentColor
        anchorDotLayer.backgroundColor = accentColor

        anchorHLineLayer.frame = CGRect(x: point.x - 8, y: point.y - 0.5, width: 16, height: 1)
        anchorVLineLayer.frame = CGRect(x: point.x - 0.5, y: point.y - 8, width: 1, height: 16)
        anchorDotLayer.frame = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)

        anchorHLineLayer.isHidden = false
        anchorVLineLayer.isHidden = false
        anchorDotLayer.isHidden = false
    }

    private func hideAnchorPreviewLayers() {
        lastRenderedAnchorPreview = nil
        if !anchorHLineLayer.isHidden { anchorHLineLayer.isHidden = true }
        if !anchorVLineLayer.isHidden { anchorVLineLayer.isHidden = true }
        if !anchorDotLayer.isHidden { anchorDotLayer.isHidden = true }
    }

    private func setInstructionVisible(_ visible: Bool) {
        if visible {
            if instructionView == nil {
                let view = OverlayInstructionView(
                    title: mode.instructionTitle,
                    caption: mode.instructionCaption(hotKeyHint: hotKeyHint)
                )
                addSubview(view)
                instructionView = view
            }
            instructionView?.center(in: bounds)
            instructionView?.isHidden = false
        } else {
            instructionView?.isHidden = true
        }
    }

    private var rawAreaSelectionRect: CGRect? {
        guard isAreaSelectionActive,
              let dragStartPoint,
              let dragCurrentPoint else { return nil }

        return CGRect(
            x: min(dragStartPoint.x, dragCurrentPoint.x),
            y: min(dragStartPoint.y, dragCurrentPoint.y),
            width: abs(dragCurrentPoint.x - dragStartPoint.x),
            height: abs(dragCurrentPoint.y - dragStartPoint.y)
        ).integral
    }

    var snapResult: EdgeSnapResult? {
        if let confirmedSnapResult { return confirmedSnapResult }
        guard let raw = rawAreaSelectionRect else { return nil }
        guard isEdgeSnappingEnabled, let map = edgeAnalysis.map else {
            return EdgeSnapResult(rect: raw, edges: [])
        }
        guard let start = dragStartPoint, let end = dragCurrentPoint else { return EdgeSnapResult(rect: raw, edges: []) }
        return EdgeSnapper.snap(from: start, to: end, map: map, anchor: startingAnchor, bypass: bypassSnapping, tolerance: edgeSnappingRange)
    }

    private func updateStartingAnchor() {
        guard isEdgeSnappingEnabled, let point = dragStartPoint, let map = edgeAnalysis.map else { return }
        let candidate = EdgeSnapper.anchor(at: point, in: map, tolerance: edgeSnappingRange)
        if startingAnchor == nil { startingAnchor = candidate }
        else {
            // Async analysis may arrive after the press. Fill missing axes, but do
            // not change a chosen origin when the endpoint or detected span changes.
            if startingAnchor?.vertical == nil { startingAnchor?.vertical = candidate.vertical }
            if startingAnchor?.horizontal == nil { startingAnchor?.horizontal = candidate.horizontal }
        }
    }

    var anchorPreviewPoint: CGPoint? {
        resolveAnchorPreviewPoint(using: snapResult)
    }

    private func resolveAnchorPreviewPoint(using activeSnapResult: EdgeSnapResult?) -> CGPoint? {
        guard isEdgeSnappingEnabled, !bypassSnapping, isPointerInsideScreen else { return nil }
        if let result = activeSnapResult, result.roundedRegion != nil,
           let start = dragStartPoint, let end = dragCurrentPoint {
            return CGPoint(x: end.x >= start.x ? result.rect.minX : result.rect.maxX,
                           y: end.y >= start.y ? result.rect.minY : result.rect.maxY)
        }
        if let startingAnchor, startingAnchor.isSnapped { return startingAnchor.previewPoint }
        guard let point = pointerPoint, let map = edgeAnalysis.map else { return nil }
        let candidate = EdgeSnapper.anchor(at: point, in: map, tolerance: edgeSnappingRange)
        return candidate.isSnapped ? candidate.previewPoint : nil
    }

    private func snappingHint(for activeSnapResult: EdgeSnapResult?) -> String {
        guard isEdgeSnappingEnabled else { return "" }
        if bypassSnapping { return " · 自由框选" }
        if edgeAnalysis.isAnalyzing { return " · 边缘识别中 · ⌥ 自由框选" }
        if edgeAnalysis.map == nil { return " · 暂无可用边缘 · 自由框选" }
        if activeSnapResult?.roundedRegion != nil { return " · 圆角贴合 · ⌥ 自由框选" }
        return (activeSnapResult?.edges.isEmpty == false ? " · 已吸附" : " · 吸附实验") + " · ⌥ 自由框选"
    }

    private var highlightedTargetRect: CGRect? {
        guard let highlightedTarget else { return nil }

        let clippedRect = highlightedTarget.highlightRect.intersection(bounds)
        guard !clippedRect.isNull, !clippedRect.isEmpty else { return nil }

        return clippedRect.integral
    }

    private func clampedPoint(for event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    private func refreshHoverState() {
        let mouseLocation = NSEvent.mouseLocation
        let isInsideCurrentScreen = screen.frame.contains(mouseLocation)

        switch mode {
        case .framed:
            let wasInside = isPointerInsideScreen
            isPointerInsideScreen = isInsideCurrentScreen
            if isInsideCurrentScreen {
                updateHighlightedTarget(at: localPoint(fromGlobalCocoaPoint: mouseLocation), forceRedraw: !wasInside)
            } else if highlightedTarget != nil || wasInside {
                highlightedTarget = nil
                updateChrome()
            }

        case .display:
            if isPointerInsideScreen != isInsideCurrentScreen {
                isPointerInsideScreen = isInsideCurrentScreen
                updateChrome()
            }
        }
    }

    private func updateHighlightedTarget(at point: CGPoint, forceRedraw: Bool = false) {
        pointerPoint = point
        let nextTarget = captureTarget(at: point)
        let targetChanged = nextTarget != highlightedTarget
        if targetChanged {
            highlightedTarget = nextTarget
        }

        if forceRedraw || targetChanged {
            updateChrome()
        } else if isEdgeSnappingEnabled, edgeAnalysis.map != nil {
            let nextPreview = resolveAnchorPreviewPoint(using: nil)
            if nextPreview != lastRenderedAnchorPreview {
                updateChrome()
            }
        }
    }

    private func dragDistance(from start: CGPoint, to end: CGPoint) -> CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }

    private func confirmAreaSelection(_ rect: CGRect, edges: [SnapEdge]) {
        guard let displaySelection = makeScreenSelection(with: rect) else {
            cancelHandler()
            return
        }

        confirmedSnapResult = EdgeSnapResult(rect: rect, edges: edges)
        captureHandler(.area(displaySelection))
    }

    private func captureTarget(at point: CGPoint) -> HighlightedCaptureTarget? {
        if let systemSurfaceTarget = systemSurfaceCaptureTarget(at: point) {
            return systemSurfaceTarget
        }

        let targets = resolvedWindowTargets()
        for target in targets where target.highlightRect.contains(point) {
            return target
        }

        return nil
    }

    private func resolvedWindowTargets() -> [HighlightedCaptureTarget] {
        if hasFrozenWindowSnapshot {
            if let preparedWindowTargets {
                return preparedWindowTargets
            }
            // Even an empty snapshot must stay empty: never select a newly appeared live window.
            let built = buildWindowTargets(from: frozenWindowInfo ?? [])
            preparedWindowTargets = built
            frozenWindowInfo = nil
            return built
        }

        let now = CACurrentMediaTime()
        if let preparedWindowTargets, (now - windowInfoCacheTime) < windowInfoCacheInterval {
            return preparedWindowTargets
        }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let list = (CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]) ?? []
        let built = buildWindowTargets(from: list)
        preparedWindowTargets = built
        windowInfoCacheTime = now
        return built
    }

    private func buildWindowTargets(from windowInfoList: [[String: Any]]) -> [HighlightedCaptureTarget] {
        var targets: [HighlightedCaptureTarget] = []
        targets.reserveCapacity(min(windowInfoList.count, 32))

        for windowInfo in windowInfoList {
            guard let selection = WindowCaptureSelection(windowInfo: windowInfo, excludingProcessID: currentProcessID)?
                .clipped(to: displayBounds) else {
                continue
            }

            let localRect = localRect(fromGlobalScreenRect: selection.bounds)
            targets.append(HighlightedCaptureTarget(
                highlightRect: localRect.integral,
                contentSize: selection.bounds.size,
                displayName: selection.displayName,
                captureRequest: .window(selection)
            ))
        }

        return targets
    }

    private func makeScreenSelection(with rect: CGRect) -> ScreenSelection? {
        guard screen.displayID != 0 else {
            return nil
        }

        return ScreenSelection(
            displayID: screen.displayID,
            rect: rect,
            scaleFactor: screen.backingScaleFactor
        )
    }

    private func makeFullScreenSelection() -> ScreenSelection? {
        makeScreenSelection(with: CGRect(origin: .zero, size: screen.frame.size))
    }

    private func systemSurfaceCaptureTarget(at point: CGPoint) -> HighlightedCaptureTarget? {
        if let menuBarRect = menuBarHighlightRect,
           menuBarRect.contains(point),
           let selection = makeScreenSelection(with: menuBarRect) {
            return HighlightedCaptureTarget(
                highlightRect: menuBarRect.integral,
                contentSize: menuBarRect.size,
                displayName: "菜单栏",
                captureRequest: .area(selection)
            )
        }

        if let dockRect = dockHighlightRect,
           dockRect.contains(point),
           let selection = makeScreenSelection(with: dockRect) {
            return HighlightedCaptureTarget(
                highlightRect: dockRect.integral,
                contentSize: dockRect.size,
                displayName: Self.resolveDockDisplayName(),
                captureRequest: .area(selection)
            )
        }

        return nil
    }

    private var menuBarHighlightRect: CGRect? {
        let topInset = screen.frame.maxY - screen.visibleFrame.maxY
        guard topInset > 0 else { return nil }

        return CGRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: topInset
        ).integral
    }

    private var dockHighlightRect: CGRect? {
        let frame = screen.frame
        let visibleFrame = screen.visibleFrame

        let leftInset = visibleFrame.minX - frame.minX
        let rightInset = frame.maxX - visibleFrame.maxX
        let bottomInset = visibleFrame.minY - frame.minY
        let topInset = frame.maxY - visibleFrame.maxY

        if bottomInset >= leftInset, bottomInset >= rightInset, bottomInset > 0 {
            return CGRect(
                x: 0,
                y: bounds.height - bottomInset,
                width: bounds.width,
                height: bottomInset
            ).integral
        }

        if leftInset >= rightInset, leftInset > 0 {
            return CGRect(
                x: 0,
                y: topInset,
                width: leftInset,
                height: bounds.height - topInset
            ).integral
        }

        if rightInset > 0 {
            return CGRect(
                x: bounds.width - rightInset,
                y: topInset,
                width: rightInset,
                height: bounds.height - topInset
            ).integral
        }

        return nil
    }

    private static func resolveDockDisplayName() -> String {
        if let cachedDockDisplayName {
            return cachedDockDisplayName
        }

        let options: CGWindowListOption = [.optionOnScreenOnly]
        guard let windowInfoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return "Dock"
        }

        for windowInfo in windowInfoList {
            let ownerName = (windowInfo[kCGWindowOwnerName as String] as? String) ?? ""
            let windowName = (windowInfo[kCGWindowName as String] as? String) ?? ""
            if windowName == "Dock", !ownerName.isEmpty {
                cachedDockDisplayName = ownerName
                return ownerName
            }
        }

        cachedDockDisplayName = "Dock"
        return "Dock"
    }

    private func localPoint(fromGlobalCocoaPoint point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x - screen.frame.minX,
            y: screen.frame.maxY - point.y
        )
    }

    private func localRect(fromGlobalScreenRect rect: CGRect) -> CGRect {
        let cocoaRect = CGRect(
            x: rect.minX,
            y: desktopTopEdge - rect.maxY,
            width: rect.width,
            height: rect.height
        )

        return CGRect(
            x: cocoaRect.minX - screen.frame.minX,
            y: screen.frame.maxY - cocoaRect.maxY,
            width: cocoaRect.width,
            height: cocoaRect.height
        )
    }
}

private extension WindowCaptureSelection {
    init?(windowInfo: [String: Any], excludingProcessID processID: pid_t) {
        guard let windowID = (windowInfo[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
              let boundsDictionary = windowInfo[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary) else {
            return nil
        }

        let ownerPID = (windowInfo[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
        let layer = (windowInfo[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        let alpha = (windowInfo[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
        let sharingState = (windowInfo[kCGWindowSharingState as String] as? NSNumber)?.intValue ?? 1
        let ownerName = (windowInfo[kCGWindowOwnerName as String] as? String) ?? "Unknown App"
        let isOnScreen = (windowInfo[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? true

        guard ownerPID != processID,
              layer == 0,
              alpha > 0.01,
              sharingState != 0,
              isOnScreen,
              bounds.width >= 60,
              bounds.height >= 60 else {
            return nil
        }

        self.init(
            windowID: windowID,
            bounds: bounds,
            ownerName: ownerName,
            windowName: windowInfo[kCGWindowName as String] as? String
        )
    }
}
