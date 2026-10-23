import SwiftUI
import QuartzCore

struct OCRScanTimeline {
    static let duration: TimeInterval = 0.45
    let id = UUID()
    let startedAt: TimeInterval

    func progress(at time: TimeInterval) -> Double {
        let fraction = min(1, max(0, (time - startedAt) / Self.duration))
        // Spatial bands are 3/11, 5/11, 3/11. The outside bands each use
        // 18% of the time; the middle uses 64%, always with positive velocity.
        if fraction <= 0.18 {
            return Self.interpolate(fraction / 0.18, from: 0, to: 3.0 / 11,
                                    startTangent: 1.8 * 0.18, endTangent: 0.18)
        }
        if fraction >= 0.82 {
            return 1 - Self.interpolate((1 - fraction) / 0.18, from: 0, to: 3.0 / 11,
                                        startTangent: 1.8 * 0.18, endTangent: 0.18)
        }
        return Self.interpolate((fraction - 0.18) / 0.64, from: 3.0 / 11, to: 8.0 / 11,
                                startTangent: 0.64, endTangent: 0.64)
    }

    private static func interpolate(_ t: Double, from start: Double, to end: Double,
                                    startTangent: Double, endTangent: Double) -> Double {
        let t2 = t * t, t3 = t2 * t
        return (2 * t3 - 3 * t2 + 1) * start + (t3 - 2 * t2 + t) * startTangent
            + (-2 * t3 + 3 * t2) * end + (t3 - t2) * endTangent
    }
}

struct OCRScanOverlay: View {
    let scan: OCRScanTimeline
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        OCRScanLayerRepresentable(scan: scan, reduceMotion: reduceMotion)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("正在识别文字")
    }
}

private struct OCRScanLayerRepresentable: NSViewRepresentable {
    let scan: OCRScanTimeline
    let reduceMotion: Bool

    func makeNSView(context: Context) -> OCRScanLayerView { OCRScanLayerView() }
    func updateNSView(_ view: OCRScanLayerView, context: Context) {
        view.configure(scan: scan, reduceMotion: reduceMotion)
    }
    static func dismantleNSView(_ view: OCRScanLayerView, coordinator: ()) { view.stopAnimation() }
}

/// The compositor moves a small layer independently of SwiftUI's render cycle.
@MainActor
final class OCRScanLayerView: NSView {
    private struct AnimationState: Equatable {
        let id: UUID
        let size: CGSize
        let reduceMotion: Bool
    }
    private let scanLine = CALayer()
    private var scan: OCRScanTimeline?
    private var reduceMotion = false
    private var appliedState: AnimationState?
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.isGeometryFlipped = true
        scanLine.anchorPoint = .zero
        scanLine.backgroundColor = NSColor.systemBlue.cgColor
        scanLine.shadowColor = NSColor.systemBlue.cgColor
        scanLine.shadowOpacity = 0.55
        scanLine.shadowRadius = 4
        scanLine.shadowOffset = .zero
        layer?.addSublayer(scanLine)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(scan: OCRScanTimeline, reduceMotion: Bool) {
        self.scan = scan
        self.reduceMotion = reduceMotion
        updateAnimation()
    }

    override func layout() {
        super.layout()
        updateAnimation()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopAnimation()
        if window != nil { updateAnimation() }
    }

    func stopAnimation() {
        scanLine.removeAnimation(forKey: "scanPosition")
        scanLine.removeAnimation(forKey: "scanVisibility")
        appliedState = nil
    }

    private func updateAnimation() {
        guard let scan, bounds.width > 0, bounds.height > 0 else { return }
        let state = AnimationState(id: scan.id, size: bounds.size, reduceMotion: reduceMotion)
        guard state != appliedState else { return }
        appliedState = state

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        scanLine.removeAnimation(forKey: "scanPosition")
        scanLine.removeAnimation(forKey: "scanVisibility")
        scanLine.bounds = CGRect(x: 0, y: 0, width: bounds.width, height: 2)
        scanLine.contentsScale = window?.backingScaleFactor ?? 2
        scanLine.shadowPath = CGPath(rect: scanLine.bounds, transform: nil)
        let travel = max(0, bounds.height - 2)
        scanLine.opacity = reduceMotion ? 1 : 0
        if reduceMotion {
            scanLine.position = CGPoint(x: 0, y: 1)
            return
        }

        // Submit one uninterrupted sweep; recognition completion never changes
        // its pacing. Absolute time avoids restarting on layout or reattachment.
        let duration = OCRScanTimeline.duration
        let elapsed = max(0, ProcessInfo.processInfo.systemUptime - scan.startedAt)
        scanLine.position = CGPoint(x: 0, y: 1 + travel)
        guard elapsed < duration else { return }
        let samples = 240
        let animation = CAKeyframeAnimation(keyPath: "position.y")
        animation.values = (0...samples).map { index in
            let time = scan.startedAt + duration * Double(index) / Double(samples)
            return 1 + travel * scan.progress(at: time)
        }
        animation.duration = duration
        animation.beginTime = scanLine.convertTime(CACurrentMediaTime(), from: nil) - elapsed
        animation.calculationMode = .linear
        animation.fillMode = .both
        scanLine.add(animation, forKey: "scanPosition")
        // Hide at the bottom instead of leaving a stationary line while OCR is
        // still working. The toolbar continues to indicate recognition activity.
        let visibility = CABasicAnimation(keyPath: "opacity")
        visibility.fromValue = 1
        visibility.toValue = 1
        visibility.duration = duration
        visibility.beginTime = animation.beginTime
        visibility.fillMode = .backwards
        scanLine.add(visibility, forKey: "scanVisibility")
    }
}
