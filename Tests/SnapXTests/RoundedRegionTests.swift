import CoreGraphics
import XCTest
@testable import SnapX

final class RoundedRegionTests: XCTestCase {
    private let size = CGSize(width: 640, height: 360)
    private let bubble = CGRect(x: 60, y: 70, width: 500, height: 160)

    func testDarkTextBubbleGetsAnOuterRectangleWithPadding() throws {
        let map = SnapEdgeDetector.detect(try fixture(), logicalSize: size)
        let region = try XCTUnwrap(map.roundedRegions.first)
        assertEncloses(region, bubble, tolerance: 2)
        let anchor = EdgeSnapper.anchor(at: CGPoint(x: 63, y: 73), in: map)
        XCTAssertEqual(anchor.previewPoint.x, 58, accuracy: 2)
        XCTAssertEqual(anchor.previewPoint.y, 68, accuracy: 2)
        let result = EdgeSnapper.snap(from: CGPoint(x: 63, y: 73), to: CGPoint(x: 556, y: 227), map: map, anchor: anchor)
        XCTAssertLessThanOrEqual(result.rect.minX, 58)
        XCTAssertLessThanOrEqual(result.rect.minY, 68)
        XCTAssertGreaterThanOrEqual(result.rect.maxX, 562)
        XCTAssertGreaterThanOrEqual(result.rect.maxY, 232)
        XCTAssertEqual(result.edges.count, 4)
    }

    func testLightBubbleAtRetinaScaleRetainsTheRoundedCorners() throws {
        let map = SnapEdgeDetector.detect(try fixture(scale: 2, dark: false), logicalSize: size)
        let result = EdgeSnapper.snap(CGRect(x: 62, y: 72, width: 496, height: 156), to: map)
        XCTAssertLessThanOrEqual(result.rect.minX, 58)
        XCTAssertGreaterThanOrEqual(result.rect.maxY, 232)
        XCTAssertEqual(result.edges.count, 4)
    }

    func testPartialSelectionAndOptionDoNotExpandToFullBubble() throws {
        let map = SnapEdgeDetector.detect(try fixture(), logicalSize: size)
        XCTAssertFalse(map.roundedRegions.isEmpty)
        let partial = CGRect(x: 120, y: 110, width: 160, height: 70)
        XCTAssertEqual(EdgeSnapper.snap(partial, to: map).rect, partial)
        let raw = CGRect(x: 63, y: 73, width: 493, height: 154)
        XCTAssertEqual(EdgeSnapper.snap(raw, to: map, bypass: true).rect, raw)
    }

    func testSmallBubbleOnLargeBackgroundIsStillFound() throws {
        let large = CGSize(width: 2560, height: 1440)
        let map = SnapEdgeDetector.detect(try fixture(dimensions: large), logicalSize: large)
        XCTAssertTrue(map.roundedRegions.contains { abs($0.minX - bubble.minX) <= 2 && abs($0.maxY - bubble.maxY) <= 2 })
    }

    func testPaddingIsClippedToScreenAndReverseDragStillIncludesWholeBubble() {
        let region = CGRect(x: 1, y: 1, width: 500, height: 160)
        let map = SnapEdgeMap(size: size, edges: [], roundedRegions: [region])
        let start = CGPoint(x: 498, y: 158), end = CGPoint(x: 4, y: 4)
        let anchor = EdgeSnapper.anchor(at: start, in: map)
        let result = EdgeSnapper.snap(from: start, to: end, map: map, anchor: anchor)
        XCTAssertEqual(result.rect, CGRect(x: 0, y: 0, width: 503, height: 163))
    }

    func testFullBubbleMatchWinsOverNeighbouringAnchor() {
        let target = CGRect(x: 85, y: 70, width: 500, height: 160)
        let neighbour = CGRect(x: 5, y: 78, width: 70, height: 60)
        let map = SnapEdgeMap(size: size, edges: [], roundedRegions: [target, neighbour])
        let start = CGPoint(x: 80, y: 73), end = CGPoint(x: 581, y: 227)
        let anchor = EdgeSnapper.anchor(at: start, in: map)
        XCTAssertEqual(anchor.previewPoint, CGPoint(x: 77, y: 76))
        let result = EdgeSnapper.snap(from: start, to: end, map: map, anchor: anchor)
        XCTAssertEqual(result.rect, CGRect(x: 83, y: 68, width: 504, height: 164))
    }

    func testSquarePanelIsNotMisclassifiedAsRoundedBubble() throws {
        let map = SnapEdgeDetector.detect(try fixture(radius: 0), logicalSize: size)
        XCTAssertTrue(map.roundedRegions.isEmpty)
    }

    func testOpenOrClippedBubbleIsNotInventedBeyondTheImage() throws {
        let map = SnapEdgeDetector.detect(try fixture(rect: CGRect(x: -30, y: 70, width: 590, height: 160)), logicalSize: size)
        XCTAssertTrue(map.roundedRegions.isEmpty)
    }

    private func assertEncloses(_ actual: CGRect, _ expected: CGRect, tolerance: CGFloat) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: tolerance)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: tolerance)
        XCTAssertEqual(actual.maxX, expected.maxX, accuracy: tolerance)
        XCTAssertEqual(actual.maxY, expected.maxY, accuracy: tolerance)
    }

    private func fixture(scale: Int = 1, dark: Bool = true, radius: Double = 30, rect: CGRect? = nil, dimensions: CGSize? = nil) throws -> CGImage {
        let rect = rect ?? bubble
        let size = dimensions ?? size
        let w = Int(size.width) * scale, h = Int(size.height) * scale
        var bytes = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h { for x in 0..<w {
            let px = (Double(x) + 0.5) / Double(scale), py = (Double(y) + 0.5) / Double(scale)
            let cx = min(max(px, rect.minX + radius), rect.maxX - radius)
            let cy = min(max(py, rect.minY + radius), rect.maxY - radius)
            let inside = rect.contains(CGPoint(x: px, y: py)) && (radius == 0 || hypot(px - cx, py - cy) <= radius)
            var value: UInt8 = inside ? (dark ? 49 : 231) : (dark ? 22 : 255)
            // Text-shaped holes must not split the surrounding bubble background.
            if inside && px > 90 && px < 530 && (100..<200).contains(py) && Int(py) % 35 < 10 && Int(px) % 18 < 10 {
                value = dark ? 230 : 30
            }
            let i = (y * w + x) * 4
            bytes[i] = value; bytes[i + 1] = value; bytes[i + 2] = value
        } }
        return try XCTUnwrap(CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData)), decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }
}
