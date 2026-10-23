import AppKit
import Vision
import XCTest
@testable import SnapX

final class OCRTests: XCTestCase {
    @MainActor
    func testResultWindowLaysOutReadableText() async throws {
        _ = NSApplication.shared
        let source = String(repeating: "SnapX 文字识别测试：长内容应自动换行，滚动后依然可以选择和复制。\n", count: 50)
        let controller = RecognizedTextWindowController(text: source, onClose: {})
        defer { controller.close() }
        let window = try XCTUnwrap(controller.window)
        let root = try XCTUnwrap(window.contentView)
        func findScroll(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap { findScroll($0) }.first
        }
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titlebarSeparatorStyle, .none)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            root.appearance = NSAppearance(named: appearance)
            for width: CGFloat in [360, 640] {
                window.setContentSize(CGSize(width: width, height: 340))
                root.layoutSubtreeIfNeeded()
                // Let the shared panel's 200 ms theme transition finish before capture.
                try await Task.sleep(nanoseconds: 250_000_000)
                let scroll = try XCTUnwrap(findScroll(root))
                scroll.layoutSubtreeIfNeeded()
                let text = try XCTUnwrap(scroll.documentView as? NSTextView)
                XCTAssertEqual(text.string, source)
                XCTAssertTrue(text.isSelectable)
                XCTAssertFalse(text.isEditable)
                XCTAssertEqual(scroll.scrollerStyle, .overlay)
                XCTAssertEqual(scroll.verticalScroller?.controlSize, .small)
                XCTAssertTrue(scroll.autohidesScrollers)
                XCTAssertFalse(scroll.drawsBackground)
                XCTAssertEqual(scroll.contentSize.width, scroll.bounds.width, accuracy: 1)
                XCTAssertEqual(text.frame.width, scroll.contentSize.width, accuracy: 2)
                XCTAssertGreaterThan(text.frame.height, scroll.contentSize.height)
                let hitPoint = scroll.convert(CGPoint(x: scroll.bounds.midX, y: scroll.bounds.midY), to: root.superview)
                XCTAssertTrue(root.hitTest(hitPoint) is NSTextView, "The result text must receive mouse selection events")
                text.setSelectedRange(NSRange(location: 0, length: 10))
                scroll.contentView.scroll(to: CGPoint(x: 0, y: 180))
                scroll.reflectScrolledClipView(scroll.contentView)
                XCTAssertGreaterThan(scroll.contentView.bounds.origin.y, 0)
                XCTAssertEqual(text.selectedRange().length, 10)
                let close = try XCTUnwrap(window.standardWindowButton(.closeButton))
                let viewport = scroll.convert(scroll.bounds, to: nil)
                XCTAssertLessThan(viewport.maxY, close.convert(close.bounds, to: nil).minY - 4)
                XCTAssertGreaterThanOrEqual(viewport.minY, 0)
                text.setSelectedRange(NSRange(location: 0, length: 0))
                scroll.contentView.scroll(to: .zero)
                scroll.reflectScrolledClipView(scroll.contentView)
                let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Build/OCRResultPreviews")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                if let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
                    root.cacheDisplay(in: root.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])?.write(to:
                        directory.appendingPathComponent("\(appearance.rawValue)-\(Int(width)).png"))
                }
            }
        }
    }

    @MainActor
    func testEditorExtractionPresentsResult() async throws {
        _ = NSApplication.shared
        // System clipboard managers can restore older contents asynchronously.
        // Isolate OCR delivery and cancellation from other running applications.
        let clipboard = NSPasteboard.withUniqueName()
        defer {
            clipboard.releaseGlobally()
            for window in NSApp.windows where window.title == "提取到的文字" { window.close() }
        }
        let image = NSImage(size: NSSize(width: 600, height: 140))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 600, height: 140).fill()
        ("SnapX OCR 12345" as NSString).draw(at: NSPoint(x: 24, y: 55), withAttributes: [
            .font: NSFont.systemFont(ofSize: 36), .foregroundColor: NSColor.black])
        image.unlockFocus()
        let controller = ScreenshotEditorWindowController(image: image, sourceRect: nil, textPasteboard: clipboard,
            onPin: { _ in }, onCopy: { _ in }, onClose: {})
        defer { controller.close() }
        controller.extractTextFromImage()
        for _ in 0..<100 {
            if clipboard.string(forType: .string)?.contains("12345") == true,
               NSApp.windows.contains(where: { $0.title == "提取到的文字" && $0.isVisible }) { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(clipboard.string(forType: .string)?.contains("12345") == true)
        XCTAssertTrue(NSApp.windows.contains(where: { $0.title == "提取到的文字" && $0.isVisible }))
        for window in NSApp.windows where window.title == "提取到的文字" { window.close() }
        clipboard.clearContents()
        XCTAssertTrue(clipboard.setString("OCR cancellation sentinel", forType: .string))
        controller.extractTextFromImage()
        controller.close()
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertEqual(clipboard.string(forType: .string), "OCR cancellation sentinel", "Closing the editor must cancel result delivery")
        XCTAssertFalse(NSApp.windows.contains(where: { $0.title == "提取到的文字" && $0.isVisible }))
    }

    @MainActor
    func testRecognizesKnownImageWithCurrentLanguages() throws {
        let image = NSImage(size: NSSize(width: 600, height: 140))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 600, height: 140).fill()
        ("截图文字 OCR 12345" as NSString).draw(at: NSPoint(x: 24, y: 55), withAttributes: [
            .font: NSFont.systemFont(ofSize: 36), .foregroundColor: NSColor.black])
        image.unlockFocus()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        let cg = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        try VNImageRequestHandler(cgImage: cg).perform([request])
        let result = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        XCTAssertTrue(result.contains("12345"), result)
        XCTAssertTrue(result.contains("截图文字"), result)
    }
}
