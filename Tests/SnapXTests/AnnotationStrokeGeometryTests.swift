import CoreGraphics
import XCTest
@testable import SnapX

final class AnnotationStrokeGeometryTests: XCTestCase {
    func testHighlighterFollowsTheRouteInsteadOfFillingItsBoundingBox() {
        let path = HighlighterGeometry.outline(points: [CGPoint(x: 10, y: 20), CGPoint(x: 80, y: 20), CGPoint(x: 80, y: 80)], width: 16)
        XCTAssertTrue(path.contains(CGPoint(x: 40, y: 20)))
        XCTAssertTrue(path.contains(CGPoint(x: 80, y: 50)))
        XCTAssertFalse(path.contains(CGPoint(x: 40, y: 50)))
    }
    func testHighlighterClickMakesOneRoundDab() {
        let path = HighlighterGeometry.outline(points: [CGPoint(x: 30, y: 30)], width: 20)
        XCTAssertTrue(path.contains(CGPoint(x: 30, y: 30)))
        XCTAssertTrue(path.contains(CGPoint(x: 38, y: 30)))
        XCTAssertFalse(path.contains(CGPoint(x: 41, y: 30)))
        XCTAssertTrue(HighlighterGeometry.outline(points: [], width: 20).isEmpty)
    }
    func testArrowFitsASmoothCurveInTheDirectionOfTheDrag() throws {
        let start = CGPoint(x: 10, y: 10), end = CGPoint(x: 110, y: 110)
        let upper = [start, CGPoint(x: 15, y: 55), CGPoint(x: 45, y: 90), end]
        let lower = [start, CGPoint(x: 55, y: 15), CGPoint(x: 90, y: 45), end]
        let a = try XCTUnwrap(CurvedArrowGeometry.controlPoint(for: upper))
        let b = try XCTUnwrap(CurvedArrowGeometry.controlPoint(for: lower))
        XCTAssertGreaterThan(a.y - a.x, 20)
        XCTAssertGreaterThan(b.x - b.y, 20)
        var quadraticSegments = 0
        CurvedArrowGeometry.path(start: start, end: end, control: a, lineWidth: 4).applyWithBlock { element in
            if element.pointee.type == .addQuadCurveToPoint { quadraticSegments += 1 }
        }
        XCTAssertEqual(quadraticSegments, 1)
    }
    func testArrowheadUsesTheCurveEndTangent() {
        let end = CGPoint(x: 100, y: 100)
        let path = CurvedArrowGeometry.path(start: .zero, end: end, control: CGPoint(x: 0, y: 100), lineWidth: 4)
        var tips: [CGPoint] = []
        path.applyWithBlock { element in
            if element.pointee.type == .addLineToPoint { tips.append(element.pointee.points[0]) }
        }
        XCTAssertEqual(tips.count, 2)
        guard tips.count == 2 else { return }
        XCTAssertLessThan(tips[0].x, end.x)
        XCTAssertLessThan(tips[1].x, end.x)
        XCTAssertEqual((tips[0].y + tips[1].y) / 2, end.y, accuracy: 0.01)
    }

    func testStraightDragStillGetsAGentleCurveAndZeroLengthIsSafe() throws {
        let control = try XCTUnwrap(CurvedArrowGeometry.controlPoint(for: [.zero, CGPoint(x: 100, y: 0)]))
        XCTAssertGreaterThan(abs(control.y), 5)
        XCTAssertLessThan(abs(control.y), 40)
        XCTAssertNil(CurvedArrowGeometry.controlPoint(for: [.zero, .zero]))
    }
}
