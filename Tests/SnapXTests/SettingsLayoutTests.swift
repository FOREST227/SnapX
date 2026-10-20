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
                start = rgb(.windowBackgroundColor)
                end = rgb(.underPageBackgroundColor)
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
