import AppKit
import XCTest
@testable import SnapX

final class AnnotationHistoryTests: XCTestCase {
    @MainActor
    func testMultipleUndoRedoRestoresOriginalOrderAndIdentity() {
        let model = ScreenshotEditorViewModel(image: NSImage(size: NSSize(width: 10, height: 10)))
        let first = annotation()
        let second = annotation()
        model.addAnnotation(first)
        model.addAnnotation(second)
        model.undoLastAnnotation()
        model.undoLastAnnotation()
        XCTAssertTrue(model.annotations.isEmpty)
        XCTAssertTrue(model.canRedo)
        model.redoLastAnnotation()
        XCTAssertEqual(model.annotations.map(\.id), [first.id])
        model.redoLastAnnotation()
        XCTAssertEqual(model.annotations.map(\.id), [first.id, second.id])
        XCTAssertFalse(model.canRedo)
        model.redoLastAnnotation()
        XCTAssertEqual(model.annotations.count, 2)
    }

    @MainActor
    func testNewAnnotationAfterUndoDiscardsRedo() {
        let model = ScreenshotEditorViewModel(image: NSImage(size: NSSize(width: 10, height: 10)))
        model.addAnnotation(annotation())
        model.undoLastAnnotation()
        let replacement = annotation()
        model.addAnnotation(replacement)
        XCTAssertFalse(model.canRedo)
        model.redoLastAnnotation()
        XCTAssertEqual(model.annotations.map(\.id), [replacement.id])
    }

    @MainActor
    func testEditingExistingAnnotationDiscardsRedo() {
        let model = ScreenshotEditorViewModel(image: NSImage(size: NSSize(width: 10, height: 10)))
        model.addAnnotation(annotation())
        model.addAnnotation(annotation())
        model.undoLastAnnotation()
        let replacement = annotation()
        model.annotations[0] = replacement
        XCTAssertFalse(model.canRedo)
        model.redoLastAnnotation()
        XCTAssertEqual(model.annotations.map(\.id), [replacement.id])
    }

    private func annotation() -> ScreenshotEditorAnnotation {
        .line(LineAnnotation(start: .zero, end: CGPoint(x: 8, y: 8), color: .red, lineWidth: 2))
    }
}
