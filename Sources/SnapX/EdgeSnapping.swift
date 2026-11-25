import CoreGraphics
import Foundation

/// All positions use display-local points with a top-left origin.
struct SnapEdge: Equatable, Sendable {
    enum Axis: Sendable { case horizontal, vertical }
    let axis: Axis
    let position: CGFloat
    let start: CGFloat
    let end: CGFloat
    let strength: CGFloat
    var lowerBound: CGFloat? = nil
    var upperBound: CGFloat? = nil
    var minimumPosition: CGFloat { lowerBound ?? position }
    var maximumPosition: CGFloat { upperBound ?? position }
}

struct SnapEdgeMap: Sendable {
    let size: CGSize
    let edges: [SnapEdge]
    let horizontalEdges: [SnapEdge]
    let verticalEdges: [SnapEdge]
    let roundedRegions: [CGRect]
    let roundedRegionsByArea: [CGRect]

    init(size: CGSize, edges: [SnapEdge], roundedRegions: [CGRect] = []) {
        self.size = size
        self.edges = edges
        self.horizontalEdges = edges.filter { $0.axis == .horizontal }
        self.verticalEdges = edges.filter { $0.axis == .vertical }
        self.roundedRegions = roundedRegions
        self.roundedRegionsByArea = roundedRegions.sorted { $0.width * $0.height < $1.width * $1.height }
    }
}

struct EdgeSnapResult: Equatable {
    let rect: CGRect
    let edges: [SnapEdge]
    var roundedRegion: CGRect? = nil
}

struct SnapAnchor: Equatable {
    let rawPoint: CGPoint
    var vertical: SnapEdge?
    var horizontal: SnapEdge?
    var isSnapped: Bool { vertical != nil || horizontal != nil }
    var previewPoint: CGPoint {
        CGPoint(x: vertical?.position ?? rawPoint.x, y: horizontal?.position ?? rawPoint.y)
    }
}

enum EdgeSnapper {
    static func anchor(at point: CGPoint, in map: SnapEdgeMap, tolerance: CGFloat = CGFloat(EdgeSnapRange.defaultValue)) -> SnapAnchor {
        let tolerance = CGFloat(EdgeSnapRange.normalized(Double(tolerance)))
        // The corner of a rounded surface is virtual: no visible edge intersects
        // there. Prefer its complete outer rectangle when the pointer is nearby.
        for region in map.roundedRegionsByArea {
            let nearLeft = abs(point.x - region.minX) <= tolerance
            let nearRight = abs(point.x - region.maxX) <= tolerance
            let nearTop = abs(point.y - region.minY) <= tolerance
            let nearBottom = abs(point.y - region.maxY) <= tolerance
            if (nearLeft || nearRight) && (nearTop || nearBottom) {
                let padded = paddedRegion(region, size: map.size)
                let sides = regionEdges(padded)
                return SnapAnchor(rawPoint: point, vertical: sides[nearLeft ? 0 : 1], horizontal: sides[nearTop ? 2 : 3])
            }
        }
        func nearest(_ axis: SnapEdge.Axis) -> SnapEdge? {
            let position = axis == .vertical ? point.x : point.y
            let along = axis == .vertical ? point.y : point.x
            let candidates = axis == .vertical ? map.verticalEdges : map.horizontalEdges
            var best: SnapEdge?
            var bestDistance = CGFloat.greatestFiniteMagnitude
            for edge in candidates {
                let distance = abs(edge.position - position)
                guard distance <= tolerance,
                      along >= edge.start - tolerance,
                      along <= edge.end + tolerance else { continue }
                if let current = best {
                    if abs(distance - bestDistance) > 0.5 {
                        if distance < bestDistance {
                            best = edge
                            bestDistance = distance
                        }
                    } else if edge.strength > current.strength {
                        best = edge
                        bestDistance = distance
                    }
                } else {
                    best = edge
                    bestDistance = distance
                }
            }
            return best
        }
        return SnapAnchor(rawPoint: point, vertical: nearest(.vertical), horizontal: nearest(.horizontal))
    }

    static func snap(from start: CGPoint, to end: CGPoint, map: SnapEdgeMap,
                     anchor: SnapAnchor?, bypass: Bool = false, tolerance: CGFloat = CGFloat(EdgeSnapRange.defaultValue)) -> EdgeSnapResult {
        let raw = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                         width: abs(end.x - start.x), height: abs(end.y - start.y)).integral
        let base = snap(raw, to: map, bypass: bypass, tolerance: tolerance)
        // All four sides identify the intended region more reliably than a
        // starting corner that may have belonged to a smaller neighbouring bubble.
        if base.roundedRegion != nil { return base }
        guard !bypass, let anchor, anchor.isSnapped else { return base }
        var x0 = base.rect.minX, x1 = base.rect.maxX, y0 = base.rect.minY, y1 = base.rect.maxY
        var edges = base.edges
        if let edge = anchor.vertical {
            let isLeft = end.x >= start.x
            edges.removeAll { candidate in
                candidate.axis == .vertical && (abs(candidate.position - raw.minX) <= abs(candidate.position - raw.maxX)) == isLeft
            }
            if isLeft { x0 = max(0, edge.minimumPosition.rounded(.down)) }
            else { x1 = min(map.size.width, edge.maximumPosition.rounded(.up)) }
            edges.append(edge)
        }
        if let edge = anchor.horizontal {
            let isTop = end.y >= start.y
            edges.removeAll { candidate in
                candidate.axis == .horizontal && (abs(candidate.position - raw.minY) <= abs(candidate.position - raw.maxY)) == isTop
            }
            if isTop { y0 = max(0, edge.minimumPosition.rounded(.down)) }
            else { y1 = min(map.size.height, edge.maximumPosition.rounded(.up)) }
            edges.append(edge)
        }
        guard x1 - x0 >= 8, y1 - y0 >= 8 else { return EdgeSnapResult(rect: raw, edges: []) }
        return EdgeSnapResult(rect: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0), edges: edges)
    }

    static func snap(_ rect: CGRect, to map: SnapEdgeMap, bypass: Bool = false, tolerance: CGFloat = CGFloat(EdgeSnapRange.defaultValue)) -> EdgeSnapResult {
        let tolerance = CGFloat(EdgeSnapRange.normalized(Double(tolerance)))
        guard !bypass, rect.width >= 24, rect.height >= 24 else {
            return EdgeSnapResult(rect: rect, edges: [])
        }
        var bestRegion: CGRect?
        var bestRegionDelta = CGFloat.greatestFiniteMagnitude
        for region in map.roundedRegions {
            guard abs(rect.minX - region.minX) <= tolerance,
                  abs(rect.maxX - region.maxX) <= tolerance,
                  abs(rect.minY - region.minY) <= tolerance,
                  abs(rect.maxY - region.maxY) <= tolerance else { continue }
            let delta = abs(rect.width - region.width) + abs(rect.height - region.height)
            if delta < bestRegionDelta {
                bestRegionDelta = delta
                bestRegion = region
            }
        }
        if let region = bestRegion {
            let padded = paddedRegion(region, size: map.size)
            return EdgeSnapResult(rect: padded, edges: regionEdges(padded), roundedRegion: region)
        }
        func nearest(axis: SnapEdge.Axis, position: CGFloat, start: CGFloat, end: CGFloat) -> SnapEdge? {
            let candidates = axis == .vertical ? map.verticalEdges : map.horizontalEdges
            let minOverlap = max(24, (end - start) * 0.55)
            var best: SnapEdge?
            var bestDistance = CGFloat.greatestFiniteMagnitude
            for edge in candidates {
                let distance = abs(edge.position - position)
                guard distance <= tolerance else { continue }
                let overlap = min(end, edge.end) - max(start, edge.start)
                guard overlap >= minOverlap else { continue }
                if let current = best {
                    if abs(distance - bestDistance) > 0.5 {
                        if distance < bestDistance {
                            best = edge
                            bestDistance = distance
                        }
                    } else if edge.strength > current.strength {
                        best = edge
                        bestDistance = distance
                    }
                } else {
                    best = edge
                    bestDistance = distance
                }
            }
            return best
        }
        let left = nearest(axis: .vertical, position: rect.minX, start: rect.minY, end: rect.maxY)
        let right = nearest(axis: .vertical, position: rect.maxX, start: rect.minY, end: rect.maxY)
        let top = nearest(axis: .horizontal, position: rect.minY, start: rect.minX, end: rect.maxX)
        let bottom = nearest(axis: .horizontal, position: rect.maxY, start: rect.minX, end: rect.maxX)
        // Include the detected border itself rather than cutting through its pixels.
        let x0 = max(0, left?.minimumPosition.rounded(.down) ?? rect.minX)
        let x1 = min(map.size.width, right?.maximumPosition.rounded(.up) ?? rect.maxX)
        let y0 = max(0, top?.minimumPosition.rounded(.down) ?? rect.minY)
        let y1 = min(map.size.height, bottom?.maximumPosition.rounded(.up) ?? rect.maxY)
        guard x1 - x0 >= 8, y1 - y0 >= 8 else { return EdgeSnapResult(rect: rect, edges: []) }
        return EdgeSnapResult(rect: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0),
                              edges: [left, right, top, bottom].compactMap { $0 })
    }
    private static func paddedRegion(_ region: CGRect, size: CGSize) -> CGRect {
        region.insetBy(dx: -2, dy: -2).integral.intersection(CGRect(origin: .zero, size: size))
    }

    private static func regionEdges(_ rect: CGRect) -> [SnapEdge] {
        [SnapEdge(axis: .vertical, position: rect.minX, start: rect.minY, end: rect.maxY, strength: 1),
         SnapEdge(axis: .vertical, position: rect.maxX, start: rect.minY, end: rect.maxY, strength: 1),
         SnapEdge(axis: .horizontal, position: rect.minY, start: rect.minX, end: rect.maxX, strength: 1),
         SnapEdge(axis: .horizontal, position: rect.maxY, start: rect.minX, end: rect.maxX, strength: 1)]
    }
}

enum SnapEdgeDetector {
    /// Bounded raster analysis. No OCR, network, or app-specific access is needed.
    static func detect(_ image: CGImage, logicalSize: CGSize) -> SnapEdgeMap {
        let empty = SnapEdgeMap(size: logicalSize, edges: [])
        guard logicalSize.width > 0, logicalSize.height > 0 else { return empty }
        let factor = min(1, 2048 / Double(max(image.width, image.height)))
        let width = max(1, Int(Double(image.width) * factor))
        let height = max(1, Int(Double(image.height) * factor))
        guard width > 2, height > 2 else { return empty }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return empty }
        let sx = logicalSize.width / CGFloat(width), sy = logicalSize.height / CGFloat(height)
        var edges: [SnapEdge] = []
        let rowBytes = width * 4
        let cancelled = pixels.withUnsafeBufferPointer { buf -> Bool in
            guard let ptr = buf.baseAddress else { return true }
            for axis in [SnapEdge.Axis.horizontal, .vertical] {
                let horizontal = axis == .horizontal
                let lines = horizontal ? height : width, length = horizontal ? width : height
                let alongScale = horizontal ? sx : sy, acrossScale = horizontal ? sy : sx
                let minLength = max(16, Int(40 / alongScale))
                let weakRequiredLength = max(minLength, Int(120 / alongScale))
                let maxGap = max(1, Int(2 / alongScale))
                let prevStride = horizontal ? rowBytes : 4
                let offsetStride = horizontal ? 4 : rowBytes
                let halfAcrossOffset: CGFloat = factor < 1 ? acrossScale / 2 : 0
                for line in 1..<lines {
                    if line & 31 == 0 && Task.isCancelled { return true }
                    var start = -1, last = -1, hits = 0, total = 0
                    let lineBase = horizontal ? line * rowBytes : line * 4
                    for offset in 0...length {
                        var difference = 0
                        if offset < length {
                            let index = lineBase + offset * offsetStride
                            let previous = index - prevStride
                            let dr = abs(Int(ptr[index]) - Int(ptr[previous]))
                            let dg = abs(Int(ptr[index + 1]) - Int(ptr[previous + 1]))
                            let db = abs(Int(ptr[index + 2]) - Int(ptr[previous + 2]))
                            difference = max(dr, max(dg, db))
                        }
                        if difference >= 8 {
                            if start < 0 { start = offset }
                            last = offset; hits += 1; total += difference
                        } else if start >= 0 && (offset - last > maxGap || offset == length) {
                            let span = last - start + 1
                            let averageContrast = Double(total) / Double(max(1, hits))
                            // Subtle dark-panel separators need a lower contrast threshold,
                            // but must be long and nearly uninterrupted to exclude text/detail.
                            let weak = averageContrast < 18
                            let requiredLength = weak ? weakRequiredLength : minLength
                            let coverage = weak ? 0.95 : 0.8
                            if span >= requiredLength && Double(hits) / Double(span) >= coverage {
                                let pos = CGFloat(line) * acrossScale
                                edges.append(SnapEdge(axis: axis, position: pos,
                                    start: CGFloat(start) * alongScale, end: CGFloat(last + 1) * alongScale,
                                    strength: CGFloat(total) / CGFloat(max(1, hits) * 255),
                                    lowerBound: pos - halfAcrossOffset,
                                    upperBound: pos + halfAcrossOffset))
                            }
                            start = -1; last = -1; hits = 0; total = 0
                        }
                    }
                }
            }
            return false
        }
        if cancelled { return empty }
        // Coalesce the two sides of a thin grid line, keeping its full span.
        var merged: [SnapEdge] = []
        merged.reserveCapacity(edges.count)
        for edge in edges.sorted(by: { a, b in
            if a.axis != b.axis { return a.axis == .horizontal }
            if a.position != b.position { return a.position < b.position }
            return a.start < b.start
        }) {
            if let index = merged.indices.reversed().prefix(32).first(where: { i in
                let previous = merged[i]
                let overlap = min(edge.end, previous.end) - max(edge.start, previous.start)
                return previous.axis == edge.axis && abs(previous.position - edge.position) <= max(1.5, 2 * (edge.axis == .horizontal ? sy : sx))
                    && overlap >= 0.9 * max(edge.end - edge.start, previous.end - previous.start)
            }) {
                let previous = merged[index]
                let lower = min(previous.minimumPosition, edge.minimumPosition)
                let upper = max(previous.maximumPosition, edge.maximumPosition)
                merged[index] = SnapEdge(axis: edge.axis, position: (lower + upper) / 2,
                    start: min(previous.start, edge.start), end: max(previous.end, edge.end),
                    strength: max(previous.strength, edge.strength), lowerBound: lower, upperBound: upper)
            } else { merged.append(edge) }
        }
        if merged.count > 4096 {
            merged = Array(merged.sorted { ($0.end - $0.start) * $0.strength > ($1.end - $1.start) * $1.strength }.prefix(4096))
        }
        let regions = RoundedRegionDetector.detect(pixels: pixels, width: width, height: height,
                                                   size: logicalSize, edges: merged)
        return SnapEdgeMap(size: logicalSize, edges: merged, roundedRegions: regions)
    }
}
