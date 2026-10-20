import AppKit
import XCTest
@testable import SnapX

final class HighlightOpacityTests: XCTestCase {
    @MainActor
    func testExportUsesTheChosenHighlightOpacity() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 20, height: 20, bitsPerComponent: 8,
            bytesPerRow: 80, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        let image = NSImage(cgImage: try XCTUnwrap(context.makeImage()), size: CGSize(width: 20, height: 20))
        var brightness: [CGFloat] = []
        for opacity in [0.25, 0.75] {
            let model = ScreenshotEditorViewModel(image: image)
            model.selectedColor = .black
            model.highlightOpacity = opacity
            model.addHighlight(rect: CGRect(x: 0, y: 0, width: 20, height: 20))
            let output = try XCTUnwrap(model.renderedImage().cgImage(forProposedRect: nil, context: nil, hints: nil))
            let color = try XCTUnwrap(NSBitmapImageRep(cgImage: output).colorAt(x: 10, y: 10)?.usingColorSpace(.deviceRGB))
            brightness.append(color.redComponent)
        }
        XCTAssertGreaterThan(brightness[0], brightness[1] + 0.2)
    }

    @MainActor
    func testNewHighlightsKeepTheirOwnOpacityThroughUndoRedo() {
        let model = ScreenshotEditorViewModel(image: NSImage(size: CGSize(width: 20, height: 20)))
        model.highlightOpacity = 0.2
        model.addHighlight(rect: CGRect(x: 1, y: 1, width: 10, height: 10))
        model.highlightOpacity = 0.8
        model.addHighlight(rect: CGRect(x: 2, y: 2, width: 10, height: 10))
        model.undoLastAnnotation()
        model.redoLastAnnotation()
        XCTAssertEqual(model.annotations.count, 2)
        guard case let .highlight(first) = model.annotations[0],
              case let .highlight(second) = model.annotations[1] else { return XCTFail("Expected highlights") }
        XCTAssertEqual(first.opacity, 0.2, accuracy: 0.001)
        XCTAssertEqual(second.opacity, 0.8, accuracy: 0.001)
    }

    @MainActor
    func testHighlightOpacityIsClampedAtTransparentAndOpaqueLimits() {
        let model = ScreenshotEditorViewModel(image: NSImage(size: CGSize(width: 20, height: 20)))
        for value in [-1.0, 2.0] {
            model.highlightOpacity = value
            model.addHighlight(rect: CGRect(x: 1, y: 1, width: 10, height: 10))
        }
        guard case let .highlight(first) = model.annotations[0],
              case let .highlight(second) = model.annotations[1] else { return XCTFail("Expected highlights") }
        XCTAssertEqual(first.opacity, 0)
        XCTAssertEqual(second.opacity, 1)
    }
}
