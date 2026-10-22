import CoreGraphics
import XCTest
@testable import SnapX

final class EdgeSnappingTests: XCTestCase {
    private let size = CGSize(width: 640, height: 400)

    func testRoughSelectionSnapsToFourTableBorders() throws {
        let map = SnapEdgeDetector.detect(try tableImage(scale: 1), logicalSize: size)
        let result = EdgeSnapper.snap(CGRect(x: 43, y: 77, width: 513, height: 147), to: map)
        XCTAssertEqual(result.rect.minX, 40, accuracy: 1.5)
        XCTAssertEqual(result.rect.maxX, 560, accuracy: 1.5)
        XCTAssertEqual(result.rect.minY, 80, accuracy: 1.5)
        XCTAssertEqual(result.rect.maxY, 220, accuracy: 1.5)
        XCTAssertEqual(result.edges.count, 4)
    }

    func testRetinaCoordinatesMatchLogicalPoints() throws {
        let map = SnapEdgeDetector.detect(try tableImage(scale: 2), logicalSize: size)
        let result = EdgeSnapper.snap(CGRect(x: 43, y: 77, width: 513, height: 147), to: map)
        XCTAssertEqual(result.rect.minX, 40, accuracy: 1.5)
        XCTAssertEqual(result.rect.minY, 80, accuracy: 1.5)
        XCTAssertEqual(result.rect.maxX, 560, accuracy: 1.5)
        XCTAssertEqual(result.rect.maxY, 220, accuracy: 1.5)
    }

    func testDownsampledLargeScreenStillFindsThinLines() throws {
        let map = SnapEdgeDetector.detect(try tableImage(scale: 4), logicalSize: size)
        let result = EdgeSnapper.snap(CGRect(x: 43, y: 77, width: 513, height: 147), to: map)
        XCTAssertEqual(result.edges.count, 4)
        XCTAssertEqual(result.rect.minX, 40, accuracy: 1.5)
        // The fixture line occupies y=220..<221; include its full extent.
        XCTAssertGreaterThanOrEqual(result.rect.maxY, 221)
        XCTAssertEqual(result.rect.maxY, 221, accuracy: 1)
    }

    func testFourKAtOneXIncludesEntireThinBorderFromEitherSide() throws {
        let large = CGSize(width: 3840, height: 2160)
        let frame = try image(scale: 1, dimensions: large) { x, y in
            let horizontal = (y == 300 || y == 1200) && (400...1600).contains(x)
            let vertical = (x == 400 || x == 1600) && (300...1200).contains(y)
            return horizontal || vertical ? 0 : 245
        }
        let map = SnapEdgeDetector.detect(frame, logicalSize: large)
        for offset in [-4.0, 4.0] {
            let result = EdgeSnapper.snap(CGRect(x: 400 + offset, y: 300 + offset, width: 1200, height: 900), to: map)
            XCTAssertEqual(result.edges.count, 4)
            XCTAssertLessThanOrEqual(result.rect.minX, 400)
            XCTAssertLessThanOrEqual(result.rect.minY, 300)
            XCTAssertGreaterThanOrEqual(result.rect.maxX, 1601)
            XCTAssertGreaterThanOrEqual(result.rect.maxY, 1201)
            XCTAssertEqual(result.rect.minX, 400, accuracy: 4)
            XCTAssertEqual(result.rect.maxY, 1201, accuracy: 4)
        }
    }

    func testPanelColorBoundaryWithoutBorderCanSnap() throws {
        let image = try image(scale: 1) { x, _ in x < 180 ? 35 : 65 }
        let map = SnapEdgeDetector.detect(image, logicalSize: size)
        let rect = CGRect(x: 184, y: 30, width: 300, height: 300)
        let result = EdgeSnapper.snap(rect, to: map)
        XCTAssertEqual(result.rect.minX, 180, accuracy: 1)
        XCTAssertEqual(result.rect.maxX, rect.maxX)
        XCTAssertEqual(result.rect.minY, rect.minY)
    }

    func testBypassAndDistantSelectionKeepExactUserRectangle() throws {
        let map = SnapEdgeDetector.detect(try tableImage(scale: 1), logicalSize: size)
        let rect = CGRect(x: 43, y: 77, width: 513, height: 147)
        XCTAssertEqual(EdgeSnapper.snap(rect, to: map, bypass: true), EdgeSnapResult(rect: rect, edges: []))
        let distant = CGRect(x: 20, y: 50, width: 580, height: 210)
        XCTAssertEqual(EdgeSnapper.snap(distant, to: map).rect, distant)
    }

    func testShortTextStrokesAndNonOverlappingEdgesAreIgnored() throws {
        let map = SnapEdgeDetector.detect(try image(scale: 1) { x, y in
            (50..<60).contains(x % 90) && (75..<90).contains(y) ? 0 : 255
        }, logicalSize: size)
        XCTAssertTrue(map.edges.isEmpty)
        let unrelated = SnapEdgeMap(size: size, edges: [SnapEdge(axis: .vertical, position: 40, start: 300, end: 399, strength: 1)])
        let rect = CGRect(x: 43, y: 77, width: 513, height: 147)
        XCTAssertEqual(EdgeSnapper.snap(rect, to: unrelated).rect, rect)
    }

    func testUniformImageAndTinySelectionNeverJump() throws {
        let blank = SnapEdgeDetector.detect(try image(scale: 1) { _, _ in 128 }, logicalSize: size)
        XCTAssertTrue(blank.edges.isEmpty)
        let table = SnapEdgeDetector.detect(try tableImage(scale: 1), logicalSize: size)
        let tiny = CGRect(x: 42, y: 82, width: 4, height: 4)
        XCTAssertEqual(EdgeSnapper.snap(tiny, to: table).rect, tiny)
    }

    private func tableImage(scale: Int) throws -> CGImage {
        try image(scale: scale) { x, y in
            let horizontal = [80, 115, 150, 185, 220].contains(y) && (40...560).contains(x)
            let vertical = [40, 170, 300, 430, 560].contains(x) && (80...220).contains(y)
            return horizontal || vertical ? 10 : 245
        }
    }

    /// Fixture bytes are top-down, matching CGImage screenshot coordinates.
    private func image(scale: Int, dimensions: CGSize? = nil, pixel: (Int, Int) -> UInt8) throws -> CGImage {
        let size = dimensions ?? size
        let width = Int(size.width) * scale, height = Int(size.height) * scale
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height { for x in 0..<width {
            let value = pixel(x / scale, y / scale), offset = (y * width + x) * 4
            bytes[offset] = value; bytes[offset + 1] = value; bytes[offset + 2] = value
        } }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        return try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }
}
