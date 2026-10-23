import CoreGraphics
import Foundation

enum HighlighterGeometry {
    /// One filled outline per mouse-down/up gesture keeps self-overlaps uniform.
    static func outline(points: [CGPoint], width: CGFloat) -> CGPath {
        let path = CGMutablePath()
        guard width.isFinite, width > 0 else { return path }
        var clean: [CGPoint] = []
        for point in points where point.x.isFinite && point.y.isFinite {
            if clean.last != point { clean.append(point) }
        }
        guard let first = clean.first else { return path }
        if clean.count == 1 {
            path.addEllipse(in: CGRect(x: first.x - width / 2, y: first.y - width / 2, width: width, height: width))
            return path
        }
        path.addLines(between: clean)
        return path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 1)
    }
}

enum CurvedArrowGeometry {
    /// Fit a single quadratic curve rather than copying small mouse jitters.
    static func controlPoint(for points: [CGPoint]) -> CGPoint? {
        let points = points.filter { $0.x.isFinite && $0.y.isFinite }
        guard let start = points.first, let end = points.last else { return nil }
        let dx = end.x - start.x, dy = end.y - start.y, length = hypot(dx, dy)
        guard length > 0.5 else { return nil }
        let ux = dx / length, uy = dy / length, nx = -uy, ny = ux
        let middle = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        var distances: [CGFloat] = [0]
        var maxDeviation: CGFloat = 0
        for index in 1..<points.count {
            distances.append(distances.last! + hypot(points[index].x - points[index - 1].x, points[index].y - points[index - 1].y))
            maxDeviation = max(maxDeviation, abs((points[index].x - start.x) * nx + (points[index].y - start.y) * ny))
        }
        let gentleBend = min(length * 0.2, 120)
        guard maxDeviation > max(3, length * 0.02), let total = distances.last, total > 0 else {
            return CGPoint(x: middle.x + nx * gentleBend, y: middle.y + ny * gentleBend)
        }
        var sumX: CGFloat = 0, sumY: CGFloat = 0, denominator: CGFloat = 0
        for index in points.indices {
            let t = distances[index] / total, u = 1 - t, weight = 2 * t * u
            sumX += weight * (points[index].x - u * u * start.x - t * t * end.x)
            sumY += weight * (points[index].y - u * u * start.y - t * t * end.y)
            denominator += weight * weight
        }
        guard denominator > 0.001 else { return middle }
        let vx = sumX / denominator - middle.x, vy = sumY / denominator - middle.y
        let along = min(length * 0.25, max(-length * 0.25, vx * ux + vy * uy))
        let bend = min(length * 0.85, max(-length * 0.85, vx * nx + vy * ny))
        return CGPoint(x: middle.x + ux * along + nx * bend, y: middle.y + uy * along + ny * bend)
    }

    static func path(start: CGPoint, end: CGPoint, control: CGPoint?, lineWidth: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let length = hypot(end.x - start.x, end.y - start.y)
        guard length > 0.5 else { return path }
        path.move(to: start)
        if let control { path.addQuadCurve(to: end, control: control) }
        else { path.addLine(to: end) }
        var tangent = CGPoint(x: end.x - (control?.x ?? start.x), y: end.y - (control?.y ?? start.y))
        if hypot(tangent.x, tangent.y) < 0.5 { tangent = CGPoint(x: end.x - start.x, y: end.y - start.y) }
        let angle = atan2(tangent.y, tangent.x)
        let head = min(max(lineWidth * 4.8, 12), length * 0.45)
        for offset in [-CGFloat.pi / 6, CGFloat.pi / 6] {
            path.move(to: end)
            path.addLine(to: CGPoint(x: end.x - cos(angle + offset) * head, y: end.y - sin(angle + offset) * head))
        }
        return path
    }
}
