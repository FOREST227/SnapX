import AppKit
import XCTest
@testable import SnapX

final class EdgeSnapRangeTests: XCTestCase {
    @MainActor func testDefaultAndPersistedRange() {
        _ = NSApplication.shared
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: EdgeSnapRange.preferenceKey)
        defer {
            if let original { defaults.set(original, forKey: EdgeSnapRange.preferenceKey) }
            else { defaults.removeObject(forKey: EdgeSnapRange.preferenceKey) }
        }
        defaults.removeObject(forKey: EdgeSnapRange.preferenceKey)
        let state = AppState()
        XCTAssertEqual(state.edgeSnappingRange, 16)
        state.setEdgeSnappingRange(24.4)
        XCTAssertEqual(state.edgeSnappingRange, 24)
        XCTAssertEqual(AppState().edgeSnappingRange, 24)
        state.setEdgeSnappingRange(1)
        XCTAssertEqual(state.edgeSnappingRange, 4)
        state.setEdgeSnappingRange(100)
        XCTAssertEqual(state.edgeSnappingRange, 32)
        state.setEdgeSnappingRange(.nan)
        XCTAssertEqual(state.edgeSnappingRange, 16)
    }

    func testConfiguredRangeChangesBothStartingAnchorAndEdges() {
        let map = SnapEdgeMap(size: CGSize(width: 640, height: 400), edges: [
            SnapEdge(axis: .vertical, position: 40, start: 0, end: 400, strength: 1),
            SnapEdge(axis: .vertical, position: 330, start: 0, end: 400, strength: 1),
            SnapEdge(axis: .horizontal, position: 80, start: 0, end: 640, strength: 1)
        ])
        let start = CGPoint(x: 52, y: 92), end = CGPoint(x: 350, y: 300)
        XCTAssertTrue(EdgeSnapper.anchor(at: start, in: map).isSnapped, "Default range must be 16pt")
        let tight = EdgeSnapper.anchor(at: start, in: map, tolerance: 4)
        XCTAssertFalse(tight.isSnapped)
        XCTAssertEqual(EdgeSnapper.snap(from: start, to: end, map: map, anchor: tight, tolerance: 4).rect.origin, start)
        let normal = EdgeSnapper.anchor(at: start, in: map, tolerance: 16)
        XCTAssertEqual(normal.previewPoint, CGPoint(x: 40, y: 80))
        XCTAssertEqual(EdgeSnapper.snap(from: start, to: end, map: map, anchor: normal, tolerance: 16).rect.origin, CGPoint(x: 40, y: 80))
        XCTAssertEqual(EdgeSnapper.snap(from: start, to: end, map: map, anchor: normal, tolerance: 32).rect.maxX, 330,
                       "The configured range must reach the moving endpoint too")
        XCTAssertEqual(EdgeSnapper.snap(from: start, to: end, map: map, anchor: normal, bypass: true, tolerance: 32).rect.origin, start)
    }

    func testConfiguredRangeAlsoAppliesToRoundedRegions() {
        let map = SnapEdgeMap(size: CGSize(width: 640, height: 400), edges: [],
                              roundedRegions: [CGRect(x: 100, y: 100, width: 200, height: 100)])
        let rect = CGRect(x: 94, y: 94, width: 212, height: 112)
        XCTAssertNil(EdgeSnapper.snap(rect, to: map, tolerance: 4).roundedRegion)
        XCTAssertNotNil(EdgeSnapper.snap(rect, to: map, tolerance: 16).roundedRegion)
    }
}
