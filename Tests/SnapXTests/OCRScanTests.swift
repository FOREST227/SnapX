import AppKit
import XCTest
@testable import SnapX

final class OCRScanTests: XCTestCase {
    func testSweepUsesSymmetricThreeFiveThreeRegionsWithoutStalling() {
        let scan = OCRScanTimeline(startedAt: 0)
        XCTAssertEqual(scan.progress(at: 0.081), 3.0 / 11, accuracy: 0.0001)
        XCTAssertEqual(scan.progress(at: 0.225), 0.5, accuracy: 0.0001)
        XCTAssertEqual(scan.progress(at: 0.369), 8.0 / 11, accuracy: 0.0001)
        XCTAssertEqual(scan.progress(at: 0.45), 1, accuracy: 0.0001)
        let outerSpeed = (3.0 / 11) / 0.081
        let middleSpeed = (scan.progress(at: 0.369) - scan.progress(at: 0.081)) / 0.288
        XCTAssertGreaterThan(outerSpeed, middleSpeed * 2)
        var previous = 0.0
        for index in 1...100 {
            let time = 0.45 * Double(index) / 100
            let progress = scan.progress(at: time)
            XCTAssertEqual(progress + scan.progress(at: 0.45 - time), 1, accuracy: 0.0001)
            XCTAssertGreaterThan(progress - previous, 0.004, "Every part of the sweep must keep moving")
            previous = progress
        }
    }

    func testRegionBoundariesDoNotChangeVelocityAbruptly() {
        let scan = OCRScanTimeline(startedAt: 0)
        for time in [0.081, 0.369] {
            let before = (scan.progress(at: time) - scan.progress(at: time - 0.00001)) / 0.00001
            let after = (scan.progress(at: time + 0.00001) - scan.progress(at: time)) / 0.00001
            XCTAssertEqual(before, after, accuracy: 0.01)
        }
    }

    @MainActor func testSlowRecognitionDoesNotPauseTheSweepOrAddAnotherExitAnimation() async throws {
        let model = ScreenshotEditorViewModel(image: NSImage(size: CGSize(width: 100, height: 100)))
        let id = model.beginTextExtraction()
        try await Task.sleep(nanoseconds: 550_000_000)
        XCTAssertTrue(model.isExtractingText, "Finishing the visual sweep must not invent a recognition result")
        XCTAssertEqual(model.ocrScan?.progress(at: ProcessInfo.processInfo.systemUptime), 1)
        let ready = ProcessInfo.processInfo.systemUptime
        let completed = try await model.finishTextExtractionScan(id: id, reduceMotion: false)
        XCTAssertTrue(completed)
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - ready, 0.1)
    }

    @MainActor func testNativeSweepDoesNotRestartOnViewUpdatesAndReducedMotionStopsIt() throws {
        let view = OCRScanLayerView(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
        let scan = OCRScanTimeline(startedAt: ProcessInfo.processInfo.systemUptime)
        view.configure(scan: scan, reduceMotion: false)
        let line = try XCTUnwrap(view.layer?.sublayers?.first)
        let initial = try XCTUnwrap(line.animation(forKey: "scanPosition") as? CAKeyframeAnimation)
        XCTAssertGreaterThan(initial.duration, 0)
        XCTAssertNotNil(line.animation(forKey: "scanVisibility"))
        XCTAssertEqual(line.opacity, 0, "After the sweep the line should disappear even if OCR is still running")
        for _ in 0..<20 { view.configure(scan: scan, reduceMotion: false) }
        let repeated = try XCTUnwrap(line.animation(forKey: "scanPosition"))
        XCTAssertEqual(initial.beginTime, repeated.beginTime, "Unrelated UI updates must not restart the scan")
        XCTAssertTrue(view.isFlipped)
        XCTAssertNil(view.hitTest(CGPoint(x: 20, y: 20)))
        view.configure(scan: scan, reduceMotion: true)
        XCTAssertNil(line.animation(forKey: "scanPosition"))
        XCTAssertNil(line.animation(forKey: "scanVisibility"))
        XCTAssertEqual(line.opacity, 1)
        XCTAssertEqual(line.position.y, 1)
        view.configure(scan: scan, reduceMotion: false)
        view.stopAnimation()
        XCTAssertNil(line.animation(forKey: "scanPosition"))
        view.configure(scan: OCRScanTimeline(startedAt: ProcessInfo.processInfo.systemUptime - 1), reduceMotion: false)
        XCTAssertNil(line.animation(forKey: "scanPosition"))
        XCTAssertNil(line.animation(forKey: "scanVisibility"))
        XCTAssertEqual(line.opacity, 0)
    }

    @MainActor func testResultsWaitForFinishingAndCancelCannotCompleteANewerScan() async throws {
        let model = ScreenshotEditorViewModel(image: NSImage(size: CGSize(width: 100, height: 100)))
        let first = model.beginTextExtraction()
        let finish = Task { try await model.finishTextExtractionScan(id: first, reduceMotion: false) }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(model.isExtractingText)
        XCTAssertEqual(model.ocrScan?.id, first)
        model.cancelTextExtraction()
        let second = model.beginTextExtraction()
        let oldFinished = try await finish.value
        XCTAssertFalse(oldFinished, "A cancelled scan must not deliver a result or dismiss the new scan")
        XCTAssertEqual(model.ocrScan?.id, second)
        let newFinished = try await model.finishTextExtractionScan(id: second, reduceMotion: false)
        XCTAssertTrue(newFinished)
        XCTAssertFalse(model.isExtractingText)
    }

    @MainActor func testImmediateRecognitionStillShowsTheFullSweep() async throws {
        let model = ScreenshotEditorViewModel(image: NSImage(size: CGSize(width: 100, height: 100)))
        let start = ProcessInfo.processInfo.systemUptime
        let id = model.beginTextExtraction()
        let completed = try await model.finishTextExtractionScan(id: id, reduceMotion: false)
        XCTAssertTrue(completed)
        XCTAssertGreaterThanOrEqual(ProcessInfo.processInfo.systemUptime - start, 0.42)
        XCTAssertFalse(model.isExtractingText)
    }

    @MainActor func testReducedMotionFinishesWithoutAnArtificialWait() async throws {
        let model = ScreenshotEditorViewModel(image: NSImage(size: CGSize(width: 100, height: 100)))
        let id = model.beginTextExtraction()
        let start = ProcessInfo.processInfo.systemUptime
        let completed = try await model.finishTextExtractionScan(id: id, reduceMotion: true)
        XCTAssertTrue(completed)
        XCTAssertFalse(model.isExtractingText)
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 0.2)
    }
}
