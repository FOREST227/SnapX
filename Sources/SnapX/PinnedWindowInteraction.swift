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
    var onTogglePassthrough: (() -> Void)? = nil
    func makeNSView(context: Context) -> PinnedDragHandleView { PinnedDragHandleView() }
    func updateNSView(_ view: PinnedDragHandleView, context: Context) { view.onTogglePassthrough = onTogglePassthrough }
}

final class PinnedDragHandleView: NSView {
    var onTogglePassthrough: (() -> Void)?
    weak var movementWindow: NSWindow?
    var passthroughActive = false { didSet { needsDisplay = true } }
    private var dragStart: CGPoint?
    private var windowOrigin = CGPoint.zero
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = "按住拖动整个钉图；双击切换鼠标穿透"
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("移动钉图")
        setAccessibilityHelp("按住鼠标左键拖动窗口；双击开启或关闭鼠标穿透")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func draw(_ dirtyRect: NSRect) {
        let image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(paletteColors: [passthroughActive ? .controlAccentColor : .labelColor]))
        let rect = CGRect(x: bounds.midX - 6, y: bounds.midY - 7, width: 12, height: 14)
        image?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
    override func mouseDown(with event: NSEvent) {
        guard event.type == .leftMouseDown else { return }
        if event.clickCount == 2 {
            dragStart = nil
            onTogglePassthrough?()
            return
        }
        if let movementWindow, let eventWindow = window {
            dragStart = eventWindow.convertPoint(toScreen: event.locationInWindow)
            windowOrigin = movementWindow.frame.origin
            NSCursor.closedHand.push()
            return
        }
        window?.makeKey()
        NSCursor.closedHand.push()
        defer { NSCursor.pop() }
        window?.performDrag(with: event)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let dragStart, let movementWindow, let eventWindow = window else { return }
        let point = eventWindow.convertPoint(toScreen: event.locationInWindow)
        movementWindow.setFrameOrigin(CGPoint(x: windowOrigin.x + point.x - dragStart.x,
                                             y: windowOrigin.y + point.y - dragStart.y))
    }
    override func mouseUp(with event: NSEvent) {
        if dragStart != nil { NSCursor.pop() }
        dragStart = nil
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
