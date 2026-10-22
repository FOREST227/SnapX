import AppKit
import SwiftUI
import XCTest
@testable import SnapX

final class SettingsLayoutTests: XCTestCase {
    @MainActor
    func testPanelDescriptionTextContrastsWithBothGradientEnds() throws {
        func luminance(_ rgb: [CGFloat]) -> Double {
            let values = rgb.map { component -> Double in
                let value = Double(component)
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return values[0] * 0.2126 + values[1] * 0.7152 + values[2] * 0.0722
        }
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            var foreground: [CGFloat] = []
            var start: [CGFloat] = []
            var end: [CGFloat] = []
            appearance.performAsCurrentDrawingAppearance {
                func rgb(_ color: NSColor) -> [CGFloat] {
                    guard let value = color.usingColorSpace(.sRGB) else { return [] }
                    return [value.redComponent, value.greenComponent, value.blueComponent]
                }
                foreground = rgb(AppPanelStyle.secondaryTextColor)
                start = rgb(AppPanelStyle.backgroundStartColor)
                end = rgb(AppPanelStyle.backgroundEndColor)
            }
            XCTAssertEqual(foreground.count, 3)
            XCTAssertEqual(start.count, 3)
            XCTAssertEqual(end.count, 3)
            guard foreground.count == 3, start.count == 3, end.count == 3 else { return }
            let gradientEnd = zip(end, start).map { $0 * 0.95 + $1 * 0.05 }
            let tint: CGFloat = name == .darkAqua ? 1 : 0
            let backgrounds = [start, gradientEnd] + [start, gradientEnd].map { $0.map { $0 * 0.95 + tint * 0.05 } }
            for background in backgrounds {
                let a = luminance(foreground)
                let b = luminance(background)
                XCTAssertGreaterThanOrEqual((max(a, b) + 0.05) / (min(a, b) + 0.05), 4.5,
                    "Descriptions must remain legible across the shared panel background")
            }
        }
    }

    @MainActor
    func testGradientUsesSameColorsAtSamePositionsRegardlessOfHeight() throws {
        for scheme in [ColorScheme.light, .dark] {
            func render(height: CGFloat) throws -> NSBitmapImageRep {
                let renderer = ImageRenderer(content: Rectangle().fill(.clear)
                    .frame(width: 320, height: height)
                    .background(AppPanelStyle.background)
                    .environment(\.colorScheme, scheme))
                renderer.scale = 1
                let image = try XCTUnwrap(renderer.nsImage)
                return try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
            }
            let short = try render(height: 600)
            let tall = try render(height: 1000)
            for point in [(20, 20), (160, 300), (300, 580)] {
                let a = try XCTUnwrap(short.colorAt(x: point.0, y: point.1)?.usingColorSpace(.sRGB))
                let b = try XCTUnwrap(tall.colorAt(x: point.0, y: point.1)?.usingColorSpace(.sRGB))
                XCTAssertEqual(a.redComponent, b.redComponent, accuracy: 0.005)
                XCTAssertEqual(a.greenComponent, b.greenComponent, accuracy: 0.005)
                XCTAssertEqual(a.blueComponent, b.blueComponent, accuracy: 0.005)
                XCTAssertEqual(a.alphaComponent, 1, accuracy: 0.005)
            }
        }
    }

    @MainActor
    func testSelectingSystemThemeClearsForcedWindowAppearance() {
        _ = NSApplication.shared
        let manager = ThemeManager.shared
        let originalTheme = manager.currentTheme
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 100, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close(); manager.currentTheme = originalTheme }
        manager.currentTheme = .dark
        XCTAssertNotNil(NSApp.appearance)
        manager.currentTheme = .system
        XCTAssertNil(NSApp.appearance)
        XCTAssertNil(window.appearance)
    }

    @MainActor
    func testRapidThemeTransitionsDoNotBlockInputOrLeaveOverlays() async throws {
        _ = NSApplication.shared
        let manager = ThemeManager.shared
        let original = manager.currentTheme
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 240, height: 160),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let content = ThemeSnapshotSpyView(frame: CGRect(x: 0, y: 0, width: 240, height: 160))
        let button = NSButton(frame: CGRect(x: 20, y: 20, width: 100, height: 30))
        content.addSubview(button)
        window.contentView = content
        window.orderFront(nil)
        defer { window.close(); manager.currentTheme = original }
        manager.currentTheme = .light
        manager.currentTheme = .dark
        manager.currentTheme = .light
        XCTAssertEqual(content.snapshotCount, 0, "Theme changes must not synchronously capture whole windows")
        XCTAssertEqual(content.subviews.count, 1, "No old-page overlay may cover the updated selection")
        try await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertEqual(content.subviews.count, 1)
        XCTAssertTrue(content.subviews.first === button)
    }

    @MainActor
    func testSettingsUsesThinOverlayScrollerWithoutGutter() async throws {
        _ = NSApplication.shared
        let state = AppState()
        let host = NSHostingView(rootView: SettingsView(appState: state))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close(); state.tearDown() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        func findScroll(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap { findScroll($0) }.first
        }
        let scroll = try XCTUnwrap(findScroll(host))
        XCTAssertEqual(scroll.scrollerStyle, .overlay)
        XCTAssertEqual(scroll.verticalScroller?.controlSize, .small)
        XCTAssertFalse(scroll.drawsBackground)
        XCTAssertEqual(scroll.contentSize.width, scroll.bounds.width, accuracy: 1)
        let document = try XCTUnwrap(scroll.documentView)
        XCTAssertGreaterThan(document.bounds.height, scroll.contentSize.height)
        scroll.contentView.scroll(to: CGPoint(x: 0, y: document.bounds.height - scroll.contentSize.height))
        scroll.reflectScrolledClipView(scroll.contentView)
        XCTAssertGreaterThan(scroll.contentView.bounds.origin.y, 0)
    }

    @MainActor
    func testSettingsTitlebarBlendsIntoContentAndRetainsWindowControls() throws {
        _ = NSApplication.shared
        let state = AppState()
        let controller = SettingsWindowController(appState: state)
        defer { controller.close(); state.tearDown() }
        let window = try XCTUnwrap(controller.window)
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titlebarSeparatorStyle, .none)
        XCTAssertFalse(try XCTUnwrap(window.standardWindowButton(.closeButton)).isHidden)
        XCTAssertFalse(try XCTUnwrap(window.standardWindowButton(.miniaturizeButton)).isHidden)
        XCTAssertTrue(window.isMovable)
    }

    @MainActor
    func testScrolledContentStaysBelowWindowButtons() async throws {
        _ = NSApplication.shared
        let state = AppState()
        let controller = SettingsWindowController(appState: state)
        defer { controller.close(); state.tearDown() }
        let window = try XCTUnwrap(controller.window)
        window.setContentSize(NSSize(width: 320, height: 600))
        let host = try XCTUnwrap(window.contentView)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 150_000_000)
        func findScroll(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap { findScroll($0) }.first
        }
        let scroll = try XCTUnwrap(findScroll(host))
        let close = try XCTUnwrap(window.standardWindowButton(.closeButton))
        let buttonFrame = close.convert(close.bounds, to: nil)
        for y: CGFloat in [0, 180, 400] {
            scroll.contentView.scroll(to: CGPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
            let viewport = scroll.convert(scroll.bounds, to: nil)
            XCTAssertLessThanOrEqual(viewport.maxY, buttonFrame.minY - 4,
                "The viewport itself must stay below the controls, even after scrolling")
        }
    }

    @MainActor
    func testShortcutErrorDetailsDoNotExpandIndicator() {
        for message in ["组合键已被占用", String(repeating: "无法注册此快捷键，请选择其他组合。", count: 20)] {
            let host = NSHostingView(rootView: ShortcutErrorIndicator(message: message, actionTitle: "框选截图", onReset: {}, onCancel: {}))
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(host.fittingSize.width, 26, accuracy: 0.5)
            XCTAssertEqual(host.fittingSize.height, 30, accuracy: 0.5)
        }
    }

    @MainActor
    func testSettingsFitsSupportedWindowWidthsInBothAppearances() throws {
        _ = NSApplication.shared
        let state = AppState()
        defer { state.tearDown() }
        let outputDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Build/SettingsPreviews")
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        for (name, colorScheme, appearance) in [
            ("light", ColorScheme.light, NSAppearance.Name.aqua),
            ("dark", ColorScheme.dark, NSAppearance.Name.darkAqua),
        ] {
            let host = NSHostingView(rootView: SettingsView(appState: state).environment(\.colorScheme, colorScheme))
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 1200),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: appearance)
            window.contentView = host
            defer { window.close() }
            host.frame = CGRect(x: 0, y: 0, width: 320, height: 1200)
            host.layoutSubtreeIfNeeded()
            XCTAssertLessThanOrEqual(host.fittingSize.width, 320, "Settings should not force horizontal scrolling")
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: outputDirectory.appendingPathComponent("settings-\(name).png"))
            host.frame.size.height = 600
            host.layoutSubtreeIfNeeded()
            XCTAssertLessThanOrEqual(host.fittingSize.width, 320)
            let mainHost = NSHostingView(rootView: MenuBarContentView(appState: state).environment(\.colorScheme, colorScheme))
            let mainWindow = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 700),
                                      styleMask: [.titled], backing: .buffered, defer: false)
            mainWindow.isReleasedWhenClosed = false
            mainWindow.appearance = NSAppearance(named: appearance)
            mainWindow.contentView = mainHost
            defer { mainWindow.close() }
            mainHost.layoutSubtreeIfNeeded()
            let mainSize = mainHost.fittingSize
            XCTAssertLessThanOrEqual(mainSize.width, 320)
            mainWindow.setContentSize(mainSize)
            mainHost.layoutSubtreeIfNeeded()
            let mainBitmap = try XCTUnwrap(mainHost.bitmapImageRepForCachingDisplay(in: mainHost.bounds))
            mainHost.cacheDisplay(in: mainHost.bounds, to: mainBitmap)
            try XCTUnwrap(mainBitmap.representation(using: .png, properties: [:]))
                .write(to: outputDirectory.appendingPathComponent("main-\(name).png"))
        }
    }
}

private final class ThemeSnapshotSpyView: NSView {
    var snapshotCount = 0
    override func cacheDisplay(in rect: NSRect, to bitmapImageRep: NSBitmapImageRep) {
        snapshotCount += 1
        super.cacheDisplay(in: rect, to: bitmapImageRep)
    }
}
