import AppKit
import XCTest
import SwiftUI
@testable import SnapX

final class EditorPreviewTests: XCTestCase {
    @MainActor
    func testEditorDrawsCapturedPixelsWithoutDependingOnDesktopBackground() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 10, height: 10, bitsPerComponent: 8,
            bytesPerRow: 40, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        let image = NSImage(cgImage: try XCTUnwrap(context.makeImage()), size: NSSize(width: 10, height: 10))
        let model = ScreenshotEditorViewModel(image: image)
        let layout = ScreenshotEditorLayout(screenFrame: CGRect(x: 0, y: 0, width: 800, height: 600),
            screenSize: CGSize(width: 800, height: 600), imageRect: CGRect(x: 20, y: 20, width: 200, height: 200),
            toolbarRect: CGRect(x: 20, y: 480, width: 650, height: 56), displayScale: 20)
        let renderer = ImageRenderer(content: ScreenshotEditorRootView(viewModel: model, layout: layout,
            onClose: {}, onDone: {}, onPin: {}, onSave: {}, onExtractText: {}))
        let output = try XCTUnwrap(renderer.cgImage)
        let bitmap = NSBitmapImageRep(cgImage: output)
        let color = try XCTUnwrap(bitmap.colorAt(x: 100, y: 170)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(color.redComponent, 0.9)
        XCTAssertGreaterThan(color.alphaComponent, 0.9)
        XCTAssertLessThan(color.blueComponent, 0.1)
    }

    @MainActor
    func testMosaicWorkIsDeferredUntilToolIsUsed() async throws {
        let counter = PreviewCounter()
        let model = ScreenshotEditorViewModel(image: NSImage(size: NSSize(width: 10, height: 10)),
            previewGenerator: { image in counter.increment(); return image })
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(counter.count, 0, "Opening the editor must not schedule unused mosaic work")
        XCTAssertNil(model.pixelatedPreviewImage)
        model.activeTool = .mosaic
        for _ in 0..<100 where model.pixelatedPreviewImage == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNotNil(model.pixelatedPreviewImage)
        XCTAssertEqual(counter.count, 1)
        model.activeTool = .rectangle
        model.activeTool = .mosaic
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(counter.count, 1, "Reusing the tool must reuse the preview")
    }
}

private final class PreviewCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    func increment() { lock.lock(); defer { lock.unlock() }; value += 1 }
}
