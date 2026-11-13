import AppKit
import SwiftUI

enum ScreenshotEditorTool: String, CaseIterable, Identifiable {
    case rectangle
    case highlight
    case text
    case arrow
    case line
    case pen
    case mosaic

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .rectangle:
            "square"
        case .highlight:
            "highlighter"
        case .text:
            "t.square"
        case .arrow:
            "arrow.up.right"
        case .line:
            "line.diagonal"
        case .pen:
            "pencil"
        case .mosaic:
            "square.grid.3x3.fill"
        }
    }

    var title: String {
        switch self {
        case .rectangle:
            "线框"
        case .highlight:
            "荧光笔"
        case .text:
            "文字"
        case .arrow:
            "弧线箭头"
        case .line:
            "直线"
        case .pen:
            "画笔"
        case .mosaic:
            "马赛克"
        }
    }

    var supportsColorSelection: Bool {
        switch self {
        case .mosaic:
            false
        case .rectangle, .highlight, .text, .arrow, .line, .pen:
            true
        }
    }

    var shortcutKey: String {
        switch self {
        case .rectangle: "1"
        case .highlight: "2"
        case .text: "3"
        case .arrow: "4"
        case .line: "5"
        case .pen: "6"
        case .mosaic: "7"
        }
    }
}

enum ScreenshotAnnotationColor: String, CaseIterable, Identifiable {
    case red
    case green
    case orange
    case yellow
    case blue
    case purple
    case darkRed
    case white
    case black

    var id: String { rawValue }

    var swiftUIColor: Color {
        switch self {
        case .red: Color(nsColor: .systemRed)
        case .green: Color(nsColor: .systemGreen)
        case .orange: Color(nsColor: .systemOrange)
        case .yellow: Color(nsColor: .systemYellow)
        case .blue: Color(nsColor: .systemBlue)
        case .purple: Color(nsColor: .systemPurple)
        case .darkRed: Color(nsColor: nsColor)
        case .white: Color.white
        case .black: Color.black
        }
    }

    var nsColor: NSColor {
        switch self {
        case .red: .systemRed
        case .green: .systemGreen
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .darkRed: NSColor(srgbRed: 0.76, green: 0.22, blue: 0.26, alpha: 1)
        case .white: .white
        case .black: .black
        }
    }

    static var highlightColors: [ScreenshotAnnotationColor] {
        [.yellow, .green, .orange, .red, .blue, .purple, .darkRed]
    }
}

enum RectangleLineStyle {
    case solid
    case dashed
    case double

    var dashPattern: [CGFloat]? {
        switch self {
        case .solid: nil
        case .dashed: [8, 4]
        case .double: nil
        }
    }
}

struct RectangleAnnotation {
    let id = UUID()
    let rect: CGRect
    let color: ScreenshotAnnotationColor
    let lineWidth: CGFloat
    let lineStyle: RectangleLineStyle
}

struct HighlightAnnotation: Identifiable {
    let id = UUID()
    var points: [CGPoint]
    let color: ScreenshotAnnotationColor
    let opacity: CGFloat
    let brushSize: CGFloat
}

struct ArrowAnnotation {
    let id = UUID()
    let start: CGPoint
    let end: CGPoint
    let color: ScreenshotAnnotationColor
    let lineWidth: CGFloat
    var controlPoint: CGPoint? = nil
}

struct LineAnnotation {
    let id = UUID()
    let start: CGPoint
    let end: CGPoint
    let color: ScreenshotAnnotationColor
    let lineWidth: CGFloat
}

struct PenAnnotation {
    let id = UUID()
    let points: [CGPoint]
    let color: ScreenshotAnnotationColor
    let lineWidth: CGFloat
}

struct TextAnnotation {
    let id = UUID()
    let origin: CGPoint
    let text: String
    let color: ScreenshotAnnotationColor
    let fontSize: CGFloat
    let isBold: Bool
    let isItalic: Bool
    let isUnderline: Bool
    var maxWidth: CGFloat? = nil
}

struct MosaicAnnotation {
    let id = UUID()
    let points: [CGPoint]
    let brushSize: CGFloat
}

enum ScreenshotEditorAnnotation: Identifiable {
    case rectangle(RectangleAnnotation)
    case highlight(HighlightAnnotation)
    case arrow(ArrowAnnotation)
    case line(LineAnnotation)
    case pen(PenAnnotation)
    case text(TextAnnotation)
    case mosaic(MosaicAnnotation)

    var id: UUID {
        switch self {
        case let .rectangle(annotation): annotation.id
        case let .highlight(annotation): annotation.id
        case let .arrow(annotation): annotation.id
        case let .line(annotation): annotation.id
        case let .pen(annotation): annotation.id
        case let .text(annotation): annotation.id
        case let .mosaic(annotation): annotation.id
        }
    }
}

struct DraftArrow {
    let start: CGPoint
    let end: CGPoint
    var controlPoint: CGPoint? = nil
}

extension ScreenshotEditorAnnotation {
    /// Recropping shifts the image's origin; annotations follow the content.
    func translated(by offset: CGSize) -> ScreenshotEditorAnnotation {
        func move(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x + offset.width, y: point.y + offset.height)
        }
        switch self {
        case let .rectangle(a):
            return .rectangle(RectangleAnnotation(rect: a.rect.offsetBy(dx: offset.width, dy: offset.height),
                color: a.color, lineWidth: a.lineWidth, lineStyle: a.lineStyle))
        case let .highlight(a):
            var moved = a
            moved.points = a.points.map(move)
            return .highlight(moved)
        case let .arrow(a):
            return .arrow(ArrowAnnotation(start: move(a.start), end: move(a.end), color: a.color,
                lineWidth: a.lineWidth, controlPoint: a.controlPoint.map(move)))
        case let .line(a):
            return .line(LineAnnotation(start: move(a.start), end: move(a.end),
                color: a.color, lineWidth: a.lineWidth))
        case let .pen(a):
            return .pen(PenAnnotation(points: a.points.map(move), color: a.color, lineWidth: a.lineWidth))
        case let .text(a):
            return .text(TextAnnotation(origin: move(a.origin), text: a.text, color: a.color,
                fontSize: a.fontSize, isBold: a.isBold, isItalic: a.isItalic,
                isUnderline: a.isUnderline, maxWidth: a.maxWidth))
        case let .mosaic(a):
            return .mosaic(MosaicAnnotation(points: a.points.map(move), brushSize: a.brushSize))
        }
    }

    /// Generous bounds including stroke spread, used to drop marks the new
    /// crop can no longer contain at all.
    var canvasBounds: CGRect {
        switch self {
        case let .rectangle(a):
            return a.rect.insetBy(dx: -a.lineWidth / 2, dy: -a.lineWidth / 2)
        case let .highlight(a):
            return Self.pointBounds(a.points).insetBy(dx: -a.brushSize / 2, dy: -a.brushSize / 2)
        case let .arrow(a):
            var points = [a.start, a.end]
            if let control = a.controlPoint { points.append(control) }
            return Self.pointBounds(points).insetBy(dx: -a.lineWidth, dy: -a.lineWidth)
        case let .line(a):
            return Self.pointBounds([a.start, a.end]).insetBy(dx: -a.lineWidth / 2, dy: -a.lineWidth / 2)
        case let .pen(a):
            return Self.pointBounds(a.points).insetBy(dx: -a.lineWidth / 2, dy: -a.lineWidth / 2)
        case let .text(a):
            return CGRect(origin: a.origin, size: CGSize(width: a.maxWidth ?? 320, height: a.fontSize * 2))
        case let .mosaic(a):
            return Self.pointBounds(a.points).insetBy(dx: -a.brushSize / 2, dy: -a.brushSize / 2)
        }
    }

    private static func pointBounds(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .null }
        return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
    }
}

struct DraftLine {
    let start: CGPoint
    let end: CGPoint
}

enum CropEdge {
    case topLeft, top, topRight
    case left, right
    case bottomLeft, bottom, bottomRight
    case move
}