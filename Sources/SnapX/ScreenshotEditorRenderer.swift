import AppKit
import CoreGraphics
@preconcurrency import CoreImage
@preconcurrency import CoreImage.CIFilterBuiltins

enum ScreenshotEditorRenderer {
    private static let ciContext = CIContext()

    static func render(image: NSImage, annotations: [ScreenshotEditorAnnotation]) -> NSImage {
        guard !annotations.isEmpty else { return image }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let source = image.cgImageRepresentation
        let scale = max(1, source.map { CGFloat($0.width) / size.width } ?? 1)
        let width = Int(ceil(size.width * scale)), height = Int(ceil(size.height * scale))
        // Standard images use nonlinear sRGB compositing to match the preview.
        // Preserve wide-gamut source profiles so unmarked P3 content is not clipped.
        guard let standardSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return image }
        let colorSpace: CGColorSpace
        if let sourceSpace = source?.colorSpace, sourceSpace.model == .rgb, sourceSpace.isWideGamutRGB {
            colorSpace = sourceSpace
        } else { colorSpace = standardSpace }
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                  bytesPerRow: width * 4, space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return image }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        defer { NSGraphicsContext.restoreGraphicsState() }
        context.scaleBy(x: scale, y: scale)
        context.interpolationQuality = .high
        image.draw(in: CGRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        if annotations.contains(where: { if case .mosaic = $0 { return true }; return false }),
           let source, let pixelated = makePixelatedCGImage(for: source) {
            drawMosaics(annotations, pixelatedImage: pixelated, in: context, size: size)
        }
        drawHighlights(annotations, in: context, size: size)
        drawVectors(annotations, in: context, size: size)
        guard let output = context.makeImage() else { return image }
        return NSImage(cgImage: output, size: size)
    }

    static func makePixelatedPreviewImage(for image: NSImage) -> NSImage? {
        guard let cgImage = image.cgImageRepresentation,
              let pixelatedCGImage = makePixelatedCGImage(for: cgImage) else {
            return nil
        }

        return NSImage(cgImage: pixelatedCGImage, size: image.size)
    }

    private static func makePixelatedCGImage(for cgImage: CGImage) -> CGImage? {
        let ciImage = CIImage(cgImage: cgImage)
        let filter = CIFilter.pixellate()
        filter.inputImage = ciImage
        filter.scale = 18

        guard let outputImage = filter.outputImage?.cropped(to: ciImage.extent) else {
            return nil
        }

        return ciContext.createCGImage(outputImage, from: outputImage.extent)
    }

    private static func drawMosaics(
        _ annotations: [ScreenshotEditorAnnotation],
        pixelatedImage: CGImage,
        in context: CGContext,
        size: CGSize
    ) {
        for annotation in annotations {
            guard case let .mosaic(mosaic) = annotation else { continue }

            if mosaic.points.count == 1, let point = mosaic.points.first {
                let convertedPoint = appKitPoint(fromTopLeftPoint: point, canvasSize: size)
                let rect = CGRect(
                    x: convertedPoint.x - (mosaic.brushSize / 2),
                    y: convertedPoint.y - (mosaic.brushSize / 2),
                    width: mosaic.brushSize,
                    height: mosaic.brushSize
                )
                context.saveGState()
                context.addEllipse(in: rect)
                context.clip()
                context.draw(pixelatedImage, in: CGRect(origin: .zero, size: size))
                context.restoreGState()
                continue
            }

            let path = CGMutablePath()
            if let first = mosaic.points.first {
                path.move(to: appKitPoint(fromTopLeftPoint: first, canvasSize: size))
                for point in mosaic.points.dropFirst() {
                    path.addLine(to: appKitPoint(fromTopLeftPoint: point, canvasSize: size))
                }
            }

            let strokedPath = path.copy(
                strokingWithWidth: mosaic.brushSize,
                lineCap: .round,
                lineJoin: .round,
                miterLimit: 1
            )

            context.saveGState()
            context.addPath(strokedPath)
            context.clip()
            context.draw(pixelatedImage, in: CGRect(origin: .zero, size: size))
            context.restoreGState()
        }
    }

    private static func drawHighlights(_ annotations: [ScreenshotEditorAnnotation], in context: CGContext, size: CGSize) {
        var transform = CGAffineTransform(translationX: 0, y: size.height).scaledBy(x: 1, y: -1)
        for annotation in annotations {
            guard case let .highlight(stroke) = annotation else { continue }
            let outline = HighlighterGeometry.outline(points: stroke.points, width: stroke.brushSize)
            guard let path = outline.copy(using: &transform) else { continue }
            context.saveGState()
            context.setBlendMode(stroke.color == .white ? .normal : .multiply)
            context.setFillColor(stroke.color.nsColor.withAlphaComponent(stroke.opacity).cgColor)
            context.addPath(path)
            context.fillPath()
            context.restoreGState()
        }
    }

    private static func drawVectors(
        _ annotations: [ScreenshotEditorAnnotation],
        in context: CGContext,
        size: CGSize
    ) {
        for annotation in annotations {
            switch annotation {
            case let .rectangle(rectangle):
                let path = CGPath(
                    roundedRect: appKitRect(fromTopLeftRect: rectangle.rect, canvasSize: size),
                    cornerWidth: 6,
                    cornerHeight: 6,
                    transform: nil
                )
                context.setStrokeColor(rectangle.color.nsColor.cgColor)
                context.setLineWidth(rectangle.lineWidth)
                context.addPath(path)
                context.strokePath()

            case .highlight:
                break // Highlighter ink is composited beneath the vector annotations.

            case let .arrow(arrow):
                var transform = CGAffineTransform(translationX: 0, y: size.height).scaledBy(x: 1, y: -1)
                let path = CurvedArrowGeometry.path(start: arrow.start, end: arrow.end,
                    control: arrow.controlPoint, lineWidth: arrow.lineWidth)
                context.setStrokeColor(arrow.color.nsColor.cgColor)
                context.setLineWidth(arrow.lineWidth)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                if let converted = path.copy(using: &transform) { context.addPath(converted) }
                context.strokePath()

            case let .line(line):
                let start = appKitPoint(fromTopLeftPoint: line.start, canvasSize: size)
                let end = appKitPoint(fromTopLeftPoint: line.end, canvasSize: size)
                context.setStrokeColor(line.color.nsColor.cgColor)
                context.setLineWidth(line.lineWidth)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.beginPath()
                context.move(to: start)
                context.addLine(to: end)
                context.strokePath()

            case let .pen(pen):
                context.setStrokeColor(pen.color.nsColor.cgColor)
                context.setLineWidth(pen.lineWidth)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.beginPath()
                if let first = pen.points.first {
                    context.move(to: appKitPoint(fromTopLeftPoint: first, canvasSize: size))
                    for point in pen.points.dropFirst() {
                        context.addLine(to: appKitPoint(fromTopLeftPoint: point, canvasSize: size))
                    }
                }
                context.strokePath()

            case let .text(text):
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byWordWrapping

                var fontTraits: NSFontDescriptor.SymbolicTraits = []
                if text.isBold {
                    fontTraits.insert(.bold)
                }
                if text.isItalic {
                    fontTraits.insert(.italic)
                }

                let baseFont = NSFont.systemFont(ofSize: text.fontSize, weight: text.isBold ? .bold : .regular)
                var font = baseFont

                if text.isItalic {
                    let descriptor = baseFont.fontDescriptor.withSymbolicTraits(fontTraits)
                    font = NSFont(descriptor: descriptor, size: text.fontSize) ?? baseFont
                }

                var attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: text.color.nsColor,
                    .paragraphStyle: paragraph,
                ]

                if text.isUnderline {
                    attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                    attributes[.underlineColor] = text.color.nsColor
                }

                let attributedText = NSAttributedString(string: text.text, attributes: attributes)
                let textHeight = max(size.height - text.origin.y - 8, text.fontSize + 12)
                let textRect = CGRect(
                    x: text.origin.x,
                    y: size.height - text.origin.y - textHeight,
                    width: max(20, min(text.maxWidth ?? (size.width - text.origin.x - 8), size.width - text.origin.x - 8)),
                    height: textHeight
                )
                attributedText.draw(in: textRect)

            case .mosaic:
                break
            }
        }
    }

    private static func appKitPoint(fromTopLeftPoint point: CGPoint, canvasSize: CGSize) -> CGPoint {
        CGPoint(
            x: point.x,
            y: canvasSize.height - point.y
        )
    }

    private static func appKitRect(fromTopLeftRect rect: CGRect, canvasSize: CGSize) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: canvasSize.height - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}

extension NSImage {
    var cgImageRepresentation: CGImage? {
        var proposedRect = CGRect(origin: .zero, size: size)
        if let cgImage = cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) {
            return cgImage
        }

        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }

        return bitmap.cgImage
    }

    var pngRepresentation: Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }
}