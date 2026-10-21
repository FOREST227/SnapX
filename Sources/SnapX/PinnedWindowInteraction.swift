import AppKit
import SwiftUI

struct PinnedResizeEdges: OptionSet {
    let rawValue: Int
    static let left = Self(rawValue: 1)
    static let right = Self(rawValue: 2)
    static let bottom = Self(rawValue: 4)
    static let top = Self(rawValue: 8)

    static func hit(at point: CGPoint, in bounds: CGRect) -> Self {
        guard bounds.contains(point) else { return [] }
        var edges: Self = []
        let margin: CGFloat = 5
        if point.x <= bounds.minX + margin { edges.insert(.left) }
        if point.x >= bounds.maxX - margin { edges.insert(.right) }
        if point.y <= bounds.minY + margin { edges.insert(.bottom) }
        if point.y >= bounds.maxY - margin { edges.insert(.top) }
        return edges
    }
    func resized(_ original: CGRect, delta: CGSize, minimum: CGSize) -> CGRect {
        var result = original
        if contains(.left) {
            result.size.width = max(minimum.width, original.width - delta.width)
            result.origin.x = original.maxX - result.width
        } else if contains(.right) { result.size.width = max(minimum.width, original.width + delta.width) }
        if contains(.bottom) {
            result.size.height = max(minimum.height, original.height - delta.height)
            result.origin.y = original.maxY - result.height
        } else if contains(.top) { result.size.height = max(minimum.height, original.height + delta.height) }
        return result
    }
}

struct PinnedDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> PinnedDragHandleView { PinnedDragHandleView() }
    func updateNSView(_ view: PinnedDragHandleView, context: Context) {}
}

final class PinnedDragHandleView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = "按住拖动整个钉图"
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("移动钉图")
        setAccessibilityHelp("按住鼠标左键拖动，移动整个钉图窗口")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func draw(_ dirtyRect: NSRect) {
        let image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(paletteColors: [.labelColor]))
        let rect = CGRect(x: bounds.midX - 6, y: bounds.midY - 7, width: 12, height: 14)
        image?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
    override func mouseDown(with event: NSEvent) {
        guard event.type == .leftMouseDown else { return }
        window?.makeKey()
        NSCursor.closedHand.push()
        defer { NSCursor.pop() }
        window?.performDrag(with: event)
    }
}

struct PinnedResizeBorder: NSViewRepresentable {
    func makeNSView(context: Context) -> PinnedResizeBorderView { PinnedResizeBorderView() }
    func updateNSView(_ view: PinnedResizeBorderView, context: Context) {}
}

final class PinnedResizeBorderView: NSView {
    private var edges: PinnedResizeEdges = []
    private var startPoint = CGPoint.zero
    private var startFrame = CGRect.zero
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return PinnedResizeEdges.hit(at: local, in: bounds).isEmpty ? nil : self
    }
    override func resetCursorRects() {
        addCursorRect(CGRect(x: 0, y: 0, width: 5, height: bounds.height), cursor: .resizeLeftRight)
        addCursorRect(CGRect(x: bounds.width - 5, y: 0, width: 5, height: bounds.height), cursor: .resizeLeftRight)
        addCursorRect(CGRect(x: 0, y: 0, width: bounds.width, height: 5), cursor: .resizeUpDown)
        addCursorRect(CGRect(x: 0, y: bounds.height - 5, width: bounds.width, height: 5), cursor: .resizeUpDown)
    }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        edges = PinnedResizeEdges.hit(at: convert(event.locationInWindow, from: nil), in: bounds)
        startFrame = window.frame
        startPoint = window.convertPoint(toScreen: event.locationInWindow)
        window.makeKey()
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window, !edges.isEmpty else { return }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        let frame = edges.resized(startFrame,
            delta: CGSize(width: point.x - startPoint.x, height: point.y - startPoint.y),
            minimum: CGSize(width: max(80, window.minSize.width), height: max(60, window.minSize.height)))
        window.setFrame(frame, display: true)
    }
    override func mouseUp(with event: NSEvent) { edges = [] }
}
