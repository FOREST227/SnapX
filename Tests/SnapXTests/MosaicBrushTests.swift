import AppKit
import SwiftUI
import XCTest
@testable import SnapX

final class MosaicBrushTests: XCTestCase {
    @MainActor
    func testEachStrokeKeepsItsSizeThroughUndoRedo() {
        let model = ScreenshotEditorViewModel(image: NSImage(size: CGSize(width: 100, height: 100)))
        model.mosaicBrushSize = 8
        model.addMosaic(points: [CGPoint(x: 20, y: 20)])
        model.mosaicBrushSize = 64
        model.addMosaic(points: [CGPoint(x: 50, y: 50)])
        model.undoLastAnnotation()
        model.redoLastAnnotation()
        guard case let .mosaic(first) = model.annotations[0],
              case let .mosaic(second) = model.annotations[1] else { return XCTFail("Expected mosaic strokes") }
        XCTAssertEqual(first.brushSize, 8)
        XCTAssertEqual(second.brushSize, 64)
    }

    @MainActor
    func testDraftMaskUsesSelectedBrushSize() throws {
        var coverage: [CGFloat] = []
        for size in [CGFloat(8), CGFloat(64)] {
            let mask = MosaicMaskView(annotations: [], draftPoints: [CGPoint(x: 50, y: 50)],
                draftBrushSize: size, imageSize: CGSize(width: 100, height: 100), displaySize: CGSize(width: 100, height: 100))
            let renderer = ImageRenderer(content: mask)
            let image = try XCTUnwrap(renderer.cgImage)
            let color = try XCTUnwrap(NSBitmapImageRep(cgImage: image).colorAt(x: 65, y: 50))
            coverage.append(color.alphaComponent)
        }
        XCTAssertLessThan(coverage[0], 0.1)
        XCTAssertGreaterThan(coverage[1], 0.9)
    }
}
