import AppKit
import XCTest
@testable import SnapX

final class HistoryWindowTests: XCTestCase {
    @MainActor
    func testHistoryWindowKeepsUsableSizeAcrossContentChanges() async throws {
        _ = NSApplication.shared
        let history = ScreenshotHistory.shared
        history.clear()
        HistoryWindowController.present(appState: AppState())
        let window = try XCTUnwrap(NSApp.windows.first { $0.title == "截图历史" })
        defer { window.close(); history.clear() }
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertGreaterThanOrEqual(window.contentView?.bounds.width ?? 0, 600)
        XCTAssertGreaterThanOrEqual(window.contentMinSize.width, 600)
        XCTAssertGreaterThanOrEqual(window.contentMinSize.height, 400)
        history.add(NSImage(size: NSSize(width: 400, height: 200)))
        window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertGreaterThanOrEqual(window.contentView?.bounds.width ?? 0, 600)
        history.clear()
        window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertGreaterThanOrEqual(window.contentView?.bounds.width ?? 0, 600)
        window.close()
        HistoryWindowController.present(appState: AppState())
        XCTAssertGreaterThanOrEqual(window.contentView?.bounds.width ?? 0, 600)
    }
    @MainActor
    func testSpaceOpensIndependentPreviewAndEscapeReturns() async throws {
        _ = NSApplication.shared
        let history = ScreenshotHistory.shared
        history.clear()
        history.add(NSImage(size: NSSize(width: 400, height: 200)))
        let controller = HistoryWindowController(appState: AppState())
        defer { controller.close(); history.clear() }
        controller.showWindow(nil)
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 150_000_000)
        func keyView(in view: NSView) -> HistoryKeyView? {
            if let key = view as? HistoryKeyView { return key }
            return view.subviews.lazy.compactMap { keyView(in: $0) }.first
        }
        let root = try XCTUnwrap(controller.window?.contentView)
        let keys = try XCTUnwrap(keyView(in: root))
        XCTAssertEqual(keys.action?(49, []), true)
        try await Task.sleep(nanoseconds: 150_000_000)
        let large = try XCTUnwrap(NSApp.windows.first { $0.title == "截图预览" && $0.isVisible })
        defer { large.close() }
        XCTAssertGreaterThanOrEqual(large.contentView?.bounds.width ?? 0, 560)
        let largeKeys = try XCTUnwrap(keyView(in: XCTUnwrap(large.contentView)))
        XCTAssertEqual(largeKeys.action?(53, []), true)
        XCTAssertFalse(large.isVisible)
        XCTAssertTrue(controller.window?.isVisible == true)
    }

}
