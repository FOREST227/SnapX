import AppKit
import XCTest
@testable import SnapX
final class StatusItemThemeTests: XCTestCase {
    @MainActor func testAppThemeDoesNotOverrideMenuBarAppearance() throws {
        _ = NSApplication.shared
        let manager = ThemeManager.shared
        let original = manager.currentTheme
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        defer { NSStatusBar.system.removeStatusItem(item); manager.currentTheme = original }
        let window = try XCTUnwrap(item.button?.window)
        manager.preserveSystemAppearance(for: window)
        let originalAppearance = window.appearance
        let originalContentAppearance = window.contentView?.appearance
        manager.currentTheme = .dark
        XCTAssertTrue(window.appearance === originalAppearance, "Status icons must retain the menu bar appearance")
        XCTAssertTrue(window.contentView?.appearance === originalContentAppearance)
    }
    @MainActor func testMenuPanelAtStatusBarLevelStillFollowsAppTheme() {
        _ = NSApplication.shared
        let manager = ThemeManager.shared
        let original = manager.currentTheme
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 320, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        defer { panel.close(); manager.currentTheme = original }
        manager.currentTheme = .dark
        XCTAssertEqual(panel.appearance?.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
        manager.currentTheme = .light
        XCTAssertEqual(panel.appearance?.bestMatch(from: [.aqua, .darkAqua]), .aqua)
        manager.currentTheme = .system
        XCTAssertNil(panel.appearance)
    }

}
