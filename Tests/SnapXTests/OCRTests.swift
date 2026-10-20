import AppKit
import Vision
import XCTest
@testable import SnapX

final class OCRTests: XCTestCase {
    @MainActor
    func testResultWindowLaysOutReadableText() throws {
        _ = NSApplication.shared
        let controller = RecognizedTextWindowController(text: String(repeating: "SnapX 文字识别测试\n", count: 50), onClose: {})
        defer { controller.close() }
        let window = try XCTUnwrap(controller.window)
        let root = try XCTUnwrap(window.contentView)
        root.layoutSubtreeIfNeeded()
        let scroll = try XCTUnwrap(root.subviews.compactMap { $0 as? NSScrollView }.first)
        scroll.layoutSubtreeIfNeeded()
        let text = try XCTUnwrap(scroll.documentView as? NSTextView)
        XCTAssertGreaterThan(scroll.contentSize.width, 200)
        XCTAssertEqual(text.frame.width, scroll.contentSize.width, accuracy: 2)
        XCTAssertGreaterThan(text.frame.height, scroll.contentSize.height, "Long results must be scrollable")
        XCTAssertGreaterThanOrEqual(scroll.frame.minY, 0)
        let safeTop = window.contentLayoutRect.maxY
        let subtitle = try XCTUnwrap(root.subviews.compactMap { $0 as? NSTextField }.first)
        XCTAssertLessThanOrEqual(subtitle.frame.maxY, safeTop, "Instructions must stay below the title bar")
    }

    @MainActor
    func testEditorExtractionPresentsResult() async throws {
        _ = NSApplication.shared
        let clipboard = NSPasteboard.general
        let savedItems = (clipboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
        defer {
            clipboard.clearContents()
            let restored = savedItems.map { data in
                let item = NSPasteboardItem()
                for (type, value) in data { item.setData(value, forType: type) }
                return item
            }
            clipboard.writeObjects(restored)
            for window in NSApp.windows where window.title == "提取到的文字" { window.close() }
        }
        let image = NSImage(size: NSSize(width: 600, height: 140))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 600, height: 140).fill()
        ("SnapX OCR 12345" as NSString).draw(at: NSPoint(x: 24, y: 55), withAttributes: [
            .font: NSFont.systemFont(ofSize: 36), .foregroundColor: NSColor.black])
        image.unlockFocus()
        let controller = ScreenshotEditorWindowController(image: image, sourceRect: nil,
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
        clipboard.setString("OCR cancellation sentinel", forType: .string)
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
