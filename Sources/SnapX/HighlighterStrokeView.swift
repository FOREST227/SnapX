import SwiftUI

/// Each stroke blends separately with the image below, matching export order.
struct HighlighterStrokeView: View {
    let stroke: HighlightAnnotation
    var scale: CGFloat = 1

    var body: some View {
        let outline = HighlighterGeometry.outline(points: stroke.points, width: stroke.brushSize)
        let path = Path(outline).applying(CGAffineTransform(scaleX: scale, y: scale))
        path.fill(stroke.color.swiftUIColor.opacity(stroke.opacity))
            .blendMode(stroke.color == .white ? .normal : .multiply)
            .allowsHitTesting(false)
    }
}
