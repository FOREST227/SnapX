import AppKit
import XCTest
@testable import SnapX
final class HistoryZoomTests: XCTestCase {
    @MainActor func testFitActualPixelsResizeAndSwitch() throws {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1600, pixelsHigh: 800,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let image = NSImage(size: NSSize(width: 800, height: 400))
        image.addRepresentation(rep)
        let first = HistoryItem(image: image, date: Date())
        let canvas = HistoryImageCanvas(frame: NSRect(x: 0, y: 0, width: 432, height: 232))
        canvas.setImage(first)
        XCTAssertTrue(canvas.fitted)
        XCTAssertEqual(canvas.scale, 0.5, accuracy: 0.001)
        canvas.actualSize()
        XCTAssertFalse(canvas.fitted)
        XCTAssertEqual(canvas.scale, 1)
        canvas.setFrameSize(NSSize(width: 832, height: 432))
        XCTAssertEqual(canvas.scale, 1, "User zoom must survive a resize")
        canvas.zoom(by: 2)
        canvas.setImage(first)
        XCTAssertEqual(canvas.scale, 2, "Unrelated SwiftUI updates must preserve zoom")
        canvas.setImage(HistoryItem(image: image, date: Date()))
        XCTAssertTrue(canvas.fitted)
        XCTAssertEqual(canvas.scale, 1, accuracy: 0.001)
        canvas.setFrameSize(NSSize(width: 432, height: 232))
        XCTAssertEqual(canvas.scale, 0.5, accuracy: 0.001)
    }
}
