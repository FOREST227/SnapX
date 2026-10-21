import AppKit
import SwiftUI

@MainActor
final class HistoryZoomState: ObservableObject {
    @Published var percent = 100
    weak var canvas: HistoryImageCanvas?
    func fit() { canvas?.fit() }
    func actualSize() { canvas?.actualSize() }
    func zoom(_ factor: CGFloat) { canvas?.zoom(by: factor) }
}

struct HistoryImageViewer: NSViewRepresentable {
    let item: HistoryItem
    @ObservedObject var zoom: HistoryZoomState
    var pinnedMode = false
    func makeNSView(context: Context) -> HistoryImageCanvas {
        let view = HistoryImageCanvas()
        view.pinnedMode = pinnedMode
        view.zoomState = zoom
        zoom.canvas = view
        if pinnedMode {
            view.wantsLayer = true
            view.layer?.cornerRadius = 6
            view.layer?.masksToBounds = true
        }
        view.setImage(item)
        return view
    }
    func updateNSView(_ view: HistoryImageCanvas, context: Context) { view.setImage(item) }
}

/// A pixel-aware viewport: scale 1 means one image pixel per display pixel.
final class HistoryImageCanvas: NSView {
    weak var zoomState: HistoryZoomState?
    var pinnedMode = false
    private var inset: CGFloat { pinnedMode ? 0 : 16 }
    override var mouseDownCanMoveWindow: Bool { false }
    private var image: NSImage?
    private var imageID: UUID?
    private var pixelSize = CGSize(width: 1, height: 1)
    private(set) var scale: CGFloat = 1
    private(set) var fitted = true
    private(set) var pan = CGPoint.zero
    private var dragOrigin: CGPoint?
    private var originalPan = CGPoint.zero
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private var backingScale: CGFloat { window?.backingScaleFactor ?? 2 }
    private var baseSize: CGSize { CGSize(width: pixelSize.width / backingScale, height: pixelSize.height / backingScale) }
    private var fitScale: CGFloat {
        let horizontal = max(bounds.width - inset * 2, 1) / baseSize.width
        let vertical = max(bounds.height - inset * 2, 1) / baseSize.height
        // Pins cover their fixed viewport; history previews show the whole image.
        return max(0.001, pinnedMode ? max(horizontal, vertical) : min(horizontal, vertical))
    }
    private var imageRect: CGRect {
        let size = CGSize(width: baseSize.width * scale, height: baseSize.height * scale)
        return CGRect(x: (bounds.width - size.width) / 2 + pan.x, y: (bounds.height - size.height) / 2 + pan.y,
                      width: size.width, height: size.height)
    }
    func setImage(_ item: HistoryItem) {
        guard imageID != item.id else { return }
        imageID = item.id
        image = item.image
        let cg = item.image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        pixelSize = cg.map { CGSize(width: $0.width, height: $0.height) } ?? item.image.size
        pixelSize.width = max(1, pixelSize.width)
        pixelSize.height = max(1, pixelSize.height)
        fit()
    }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateViewport()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if fitted && pan == .zero { fit() } else { updateViewport() }
    }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateViewport()
    }
    private func updateViewport() {
        if pinnedMode {
            // Layout passes and viewport resizing must not silently recenter a pin.
            let next = max(scale, fitScale)
            let ratio = next / scale
            pan.x *= ratio
            pan.y *= ratio
            scale = next
            fitted = scale == fitScale
            clampPan()
            update()
        } else if fitted {
            fit()
        } else {
            clampPan()
            update()
        }
    }
    func fit() {
        fitted = true
        scale = fitScale
        pan = .zero
        update()
    }
    func actualSize() {
        if pinnedMode {
            zoom(by: max(1, fitScale) / scale)
            return
        }
        scale = 1
        fitted = false
        pan = .zero
        clampPan()
        update()
    }
    func zoom(by factor: CGFloat, at anchor: CGPoint? = nil) {
        guard factor.isFinite, factor > 0 else { return }
        let point = anchor ?? CGPoint(x: bounds.midX, y: bounds.midY)
        let old = imageRect
        let minimum = pinnedMode ? fitScale : min(0.01, fitScale)
        let next = min(max(scale * factor, minimum), max(20, fitScale))
        let ratio = next / scale
        pan.x = point.x - bounds.midX - (point.x - old.midX) * ratio
        pan.y = point.y - bounds.midY - (point.y - old.midY) * ratio
        scale = next
        fitted = pinnedMode && next == fitScale
        clampPan()
        update()
    }
    private func clampPan() {
        let limitX = max(0, (baseSize.width * scale - bounds.width) / 2 + inset)
        let limitY = max(0, (baseSize.height * scale - bounds.height) / 2 + inset)
        pan.x = min(max(pan.x, -limitX), limitX)
        pan.y = min(max(pan.y, -limitY), limitY)
    }
    private func update() {
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        let percent = Int((scale * 100).rounded())
        DispatchQueue.main.async { [weak self] in
            guard let self, self.zoomState?.percent != percent else { return }
            self.zoomState?.percent = percent
        }
    }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: imageRect.width > bounds.width || imageRect.height > bounds.height ? .openHand : .arrow)
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        guard let image else { return }
        let rect = imageRect
        NSGraphicsContext.saveGraphicsState()
        let visible = rect.intersection(bounds)
        guard !visible.isNull else { NSGraphicsContext.restoreGraphicsState(); return }
        visible.clip()
        NSColor.controlBackgroundColor.setFill()
        rect.fill()
        // Draw only visible checkerboard tiles, including when heavily zoomed.
        let tile: CGFloat = 10
        for row in Int(floor(visible.minY / tile))...Int(ceil(visible.maxY / tile)) {
            for column in Int(floor(visible.minX / tile))...Int(ceil(visible.maxX / tile)) where (row + column) % 2 == 0 {
                NSColor.separatorColor.withAlphaComponent(0.18).setFill()
                CGRect(x: CGFloat(column) * tile, y: CGFloat(row) * tile, width: tile, height: tile).fill()
            }
        }
        NSGraphicsContext.current?.imageInterpolation = !pinnedMode && scale >= 1 ? .none : .high
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        NSColor.separatorColor.setStroke()
        NSBezierPath(rect: rect).stroke()
    }
    override func scrollWheel(with event: NSEvent) {
        // Precision alone also describes smooth/high-resolution mouse wheels.
        let trackpadScroll = !event.phase.isEmpty || !event.momentumPhase.isEmpty
        if trackpadScroll {
            pan.x -= event.scrollingDeltaX
            pan.y += event.scrollingDeltaY
            clampPan(); update()
        } else {
            zoom(by: exp(event.scrollingDeltaY * 0.04), at: convert(event.locationInWindow, from: nil))
        }
    }
    override func magnify(with event: NSEvent) {
        zoom(by: max(0.1, 1 + event.magnification), at: convert(event.locationInWindow, from: nil))
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if pinnedMode && event.modifierFlags.contains(.option) {
            dragOrigin = nil
            NSCursor.closedHand.push()
            defer { NSCursor.pop() }
            window?.performDrag(with: event)
            return
        }
        if event.clickCount == 2 {
            if fitted { actualSize() } else { fit() }
            return
        }
        dragOrigin = convert(event.locationInWindow, from: nil)
        originalPan = pan
        NSCursor.closedHand.push()
    }
    override func mouseDragged(with event: NSEvent) {
        guard let dragOrigin else { return }
        let current = convert(event.locationInWindow, from: nil)
        pan = CGPoint(x: originalPan.x + current.x - dragOrigin.x, y: originalPan.y + current.y - dragOrigin.y)
        clampPan(); update()
    }
    override func mouseUp(with event: NSEvent) {
        if dragOrigin != nil { NSCursor.pop() }
        dragOrigin = nil
    }
}

struct HistoryKeyboardHandler: NSViewRepresentable {
    let action: (UInt16, NSEvent.ModifierFlags) -> Bool
    func makeNSView(context: Context) -> HistoryKeyView { HistoryKeyView() }
    func updateNSView(_ view: HistoryKeyView, context: Context) { view.action = action }
    static func dismantleNSView(_ view: HistoryKeyView, coordinator: ()) { view.removeMonitor() }
}
final class HistoryKeyView: NSView {
    var action: ((UInt16, NSEvent.ModifierFlags) -> Bool)?
    private var monitor: Any?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true,
                  !(self.window?.firstResponder is NSTextView) else { return event }
            return self.action?(event.keyCode, event.modifierFlags.intersection(.deviceIndependentFlagsMask)) == true ? nil : event
        }
    }
    func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
