import AppKit
import SwiftUI

/// Native click counts let the first click act immediately without waiting for
/// a SwiftUI exclusive double-tap recognizer to fail.
struct EditorTextInteraction: NSViewRepresentable {
    let onTap: (CGPoint, Bool) -> Void
    let onDrag: (CGPoint, CGPoint) -> Void
    let onDragEnd: () -> Void
    func makeNSView(context: Context) -> EditorTextInteractionView { EditorTextInteractionView() }
    func updateNSView(_ view: EditorTextInteractionView, context: Context) {
        view.onTap = onTap; view.onDrag = onDrag; view.onDragEnd = onDragEnd
    }
}

final class EditorTextInteractionView: NSView {
    var onTap: ((CGPoint, Bool) -> Void)?
    var onDrag: ((CGPoint, CGPoint) -> Void)?
    var onDragEnd: (() -> Void)?
    private var start: CGPoint?
    private var clickCount = 1
    private var dragged = false

    override func mouseDown(with event: NSEvent) {
        start = point(event)
        clickCount = event.clickCount
        dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let current = point(event)
        if hypot(current.x - start.x, current.y - start.y) > 3 { dragged = true }
        if dragged { onDrag?(start, current) }
    }
    override func mouseUp(with event: NSEvent) {
        guard start != nil else { return }
        defer { start = nil; dragged = false }
        if dragged { onDragEnd?() }
        else { onTap?(point(event), clickCount >= 2) }
    }
    private func point(_ event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(max(local.x, 0), bounds.width), y: min(max(local.y, 0), bounds.height))
    }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
