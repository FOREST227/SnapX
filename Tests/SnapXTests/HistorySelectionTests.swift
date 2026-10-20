import XCTest
@testable import SnapX
final class HistorySelectionTests: XCTestCase {
    func testRangeAndCommandSelection() {
        let ids = (0..<5).map { _ in UUID() }
        var selection = HistorySelection()
        selection.reconcile(ids)
        selection.select(ids[2], in: ids, shift: true)
        XCTAssertEqual(selection.selectedIDs, Set(ids[0...2]))
        selection.select(ids[1], in: ids)
        selection.select(ids[3], in: ids, shift: true)
        XCTAssertEqual(selection.selectedIDs, Set(ids[1...3]))
        selection.select(ids[2], in: ids, command: true)
        XCTAssertEqual(selection.selectedIDs, [ids[1], ids[3]])
        selection.move(1, in: ids)
        XCTAssertEqual(selection.selectedIDs, [ids[1], ids[3]], "Navigation preserves batch selection")
    }
    func testDeletingFocusSelectsNextAndNavigationClamps() {
        let ids = (0..<4).map { _ in UUID() }
        var selection = HistorySelection()
        selection.select(ids[1], in: ids)
        selection.reconcile([ids[0], ids[2], ids[3]])
        XCTAssertEqual(selection.focusedID, ids[2])
        selection.move(20, in: [ids[0], ids[2], ids[3]])
        XCTAssertEqual(selection.focusedID, ids[3])
        selection.reconcile([])
        XCTAssertNil(selection.focusedID)
        XCTAssertTrue(selection.selectedIDs.isEmpty)
    }
}
