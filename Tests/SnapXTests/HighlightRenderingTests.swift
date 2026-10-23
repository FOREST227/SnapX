import AppKit
import SwiftUI
import XCTest
@testable import SnapX

final class HighlightRenderingTests: XCTestCase {
    @MainActor func testOneStrokeDoesNotAccumulateInkAtSelfOverlapsButSeparateStrokesDo() throws {
        let image = try background()
        let line = [CGPoint(x: 10, y: 50), CGPoint(x: 90, y: 50)]
        let once = HighlightAnnotation(points: line, color: .black, opacity: 0.4, brushSize: 16)
        let retraced = HighlightAnnotation(points: line + line.reversed(), color: .black, opacity: 0.4, brushSize: 16)
        let second = HighlightAnnotation(points: line, color: .black, opacity: 0.4, brushSize: 16)
        let a = try color(ScreenshotEditorRenderer.render(image: image, annotations: [.highlight(once)]), at: CGPoint(x: 30, y: 50))
        let b = try color(ScreenshotEditorRenderer.render(image: image, annotations: [.highlight(retraced)]), at: CGPoint(x: 30, y: 50))
        let c = try color(ScreenshotEditorRenderer.render(image: image, annotations: [.highlight(once), .highlight(second)]), at: CGPoint(x: 30, y: 50))
        XCTAssertEqual(a.redComponent, b.redComponent, accuracy: 0.02)
        XCTAssertLessThan(c.redComponent, a.redComponent - 0.1)
    }

    @MainActor func testPreviewAndExportPreserveBlackContentAndAgreeWhenStrokesOverlap() throws {
        let image = try background()
        let strokes = [
            HighlightAnnotation(points: [CGPoint(x: 10, y: 50), CGPoint(x: 90, y: 50)], color: .yellow, opacity: 0.5, brushSize: 16),
            HighlightAnnotation(points: [CGPoint(x: 65, y: 10), CGPoint(x: 65, y: 90)], color: .blue, opacity: 0.4, brushSize: 16)
        ]
        let renderer = ImageRenderer(content: ZStack(alignment: .topLeading) {
            Image(nsImage: image).resizable().frame(width: 100, height: 100)
            ZStack(alignment: .topLeading) {
                ForEach(strokes) { HighlighterStrokeView(stroke: $0) }
            }.frame(width: 100, height: 100).clipped()
        }.frame(width: 100, height: 100))
        renderer.scale = 1
        let preview = try XCTUnwrap(renderer.nsImage)
        let exported = ScreenshotEditorRenderer.render(image: image, annotations: strokes.map { .highlight($0) })
        let dark = try color(exported, at: CGPoint(x: 50, y: 50))
        XCTAssertLessThan(dark.redComponent, 0.02)
        XCTAssertLessThan(dark.greenComponent, 0.02)
        for point in [CGPoint(x: 30, y: 50), CGPoint(x: 50, y: 50), CGPoint(x: 65, y: 50), CGPoint(x: 65, y: 25)] {
            let a = try color(preview, at: point), b = try color(exported, at: point)
            XCTAssertEqual(a.redComponent, b.redComponent, accuracy: 0.07)
            XCTAssertEqual(a.greenComponent, b.greenComponent, accuracy: 0.07)
            XCTAssertEqual(a.blueComponent, b.blueComponent, accuracy: 0.07)
        }
    }

    @MainActor func testTransparentInkPreservesWideGamutPixelsOutsideTheStroke() throws {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let context = try XCTUnwrap(CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8,
            bytesPerRow: 400, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(try XCTUnwrap(CGColor(colorSpace: space, components: [1, 0, 0, 1])))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        let image = NSImage(cgImage: try XCTUnwrap(context.makeImage()), size: CGSize(width: 100, height: 100))
        let stroke = HighlightAnnotation(points: [CGPoint(x: 10, y: 50), CGPoint(x: 90, y: 50)], color: .yellow, opacity: 0, brushSize: 16)
        let output = try XCTUnwrap(ScreenshotEditorRenderer.render(image: image, annotations: [.highlight(stroke)]).cgImageRepresentation)
        let comparison = try XCTUnwrap(CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8,
            bytesPerRow: 400, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        comparison.draw(output, in: CGRect(x: 0, y: 0, width: 100, height: 100))
        let bytes = try XCTUnwrap(comparison.data).assumingMemoryBound(to: UInt8.self)
        for point in [(20, 20), (50, 50)] {
            let i = (point.1 * 100 + point.0) * 4
            XCTAssertGreaterThanOrEqual(bytes[i], 253)
            XCTAssertLessThanOrEqual(bytes[i + 1], 2)
            XCTAssertLessThanOrEqual(bytes[i + 2], 2)
        }
    }

    @MainActor func testExportPreservesRetinaPixelDensity() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8,
            bytesPerRow: 800, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        let base = NSImage(cgImage: try XCTUnwrap(context.makeImage()), size: CGSize(width: 100, height: 100))
        let stroke = HighlightAnnotation(points: [CGPoint(x: 10, y: 50), CGPoint(x: 90, y: 50)], color: .yellow, opacity: 0.5, brushSize: 16)
        let result = ScreenshotEditorRenderer.render(image: base, annotations: [.highlight(stroke)])
        let output = try XCTUnwrap(result.cgImageRepresentation)
        XCTAssertEqual(output.width, 200)
        XCTAssertEqual(output.height, 200)
        XCTAssertEqual(result.size, base.size)
    }

    @MainActor func testStrokeWidthAndPathRemainUnchangedAfterUndoRedo() {
        let model = ScreenshotEditorViewModel(image: NSImage(size: CGSize(width: 100, height: 100)))
        let points = [CGPoint(x: 10, y: 20), CGPoint(x: 80, y: 20), CGPoint(x: 80, y: 80)]
        model.highlightBrushSize = 12
        model.addHighlight(points: points)
        model.highlightBrushSize = 48
        model.addHighlight(points: [.zero])
        model.undoLastAnnotation(); model.redoLastAnnotation()
        guard case let .highlight(first) = model.annotations[0], case let .highlight(second) = model.annotations[1] else { return XCTFail("Expected strokes") }
        XCTAssertEqual(first.points, points)
        XCTAssertEqual(first.brushSize, 12)
        XCTAssertEqual(second.brushSize, 48)
        model.addHighlight(points: [])
        XCTAssertEqual(model.annotations.count, 2)
    }

    @MainActor private func background() throws -> NSImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8,
            bytesPerRow: 400, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        context.setFillColor(NSColor.black.cgColor); context.fill(CGRect(x: 45, y: 0, width: 10, height: 100))
        return NSImage(cgImage: try XCTUnwrap(context.makeImage()), size: CGSize(width: 100, height: 100))
    }
    @MainActor private func color(_ image: NSImage, at point: CGPoint) throws -> NSColor {
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(image.cgImageRepresentation))
        let x = Int(point.x * CGFloat(bitmap.pixelsWide) / image.size.width)
        let y = Int(point.y * CGFloat(bitmap.pixelsHigh) / image.size.height)
        return try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
    }
}
