import CoreGraphics
import Foundation

/// Finds closed, nearly uniform rounded surfaces; text is allowed as holes inside.
/// Uses the existing bounded analysis raster and never modifies screenshot pixels.
enum RoundedRegionDetector {
    static func detect(pixels: [UInt8], width: Int, height: Int, size: CGSize, edges: [SnapEdge]) -> [CGRect] {
        let sx = size.width / CGFloat(width), sy = size.height / CGFloat(height)
        let seeds = edges.filter { $0.axis == .horizontal && $0.end - $0.start >= 48 }
            .sorted { $0.end - $0.start > $1.end - $1.start }.prefix(96)
        guard !seeds.isEmpty else { return [] }
        var labels = [UInt16](repeating: 0, count: width * height)
        var queue: [Int32] = []
        var regions: [CGRect] = []
        var label: UInt16 = 0
        for edge in seeds {
            if Task.isCancelled { return [] }
            let x = min(width - 1, max(0, Int((edge.start + edge.end) / (2 * sx))))
            let y = Int(edge.position / sy)
            let top = max(0, y - 3), bottom = min(height - 1, y + 3)
            let a = (top * width + x) * 4, b = (bottom * width + x) * 4
            let contrast = (0..<3).map { abs(Int(pixels[a + $0]) - Int(pixels[b + $0])) }.max() ?? 0
            guard contrast >= 8 else { continue }
            let colorTolerance = max(3, min(10, Int(Double(contrast) * 0.35)))
            for seedY in [top, bottom] {
                let seed = seedY * width + x
                guard labels[seed] == 0 else { continue }
                label += 1
                let seedOffset = seed * 4
                let red = Int(pixels[seedOffset]), green = Int(pixels[seedOffset + 1]), blue = Int(pixels[seedOffset + 2])
                queue.removeAll(keepingCapacity: true)
                queue.append(Int32(seed)); labels[seed] = label
                var head = 0, minX = x, maxX = x, minY = seedY, maxY = seedY
                while head < queue.count {
                    if head % 4096 == 0 && Task.isCancelled { return [] }
                    // The raster is capped at 2048 per side and each pixel is
                    // visited once. Finish large backgrounds so later bubbles are not skipped.
                    let index = Int(queue[head]); head += 1
                    let px = index % width, py = index / width
                    minX = min(minX, px); maxX = max(maxX, px)
                    minY = min(minY, py); maxY = max(maxY, py)
                    for next in [px > 0 ? index - 1 : -1, px + 1 < width ? index + 1 : -1,
                                 py > 0 ? index - width : -1, py + 1 < height ? index + width : -1] {
                        guard next >= 0, labels[next] == 0 else { continue }
                        let offset = next * 4
                        if abs(Int(pixels[offset]) - red) <= colorTolerance &&
                            abs(Int(pixels[offset + 1]) - green) <= colorTolerance &&
                            abs(Int(pixels[offset + 2]) - blue) <= colorTolerance {
                            labels[next] = label; queue.append(Int32(next))
                        }
                    }
                }
                let w = maxX - minX + 1, h = maxY - minY + 1
                guard minX > 1, minY > 1, maxX < width - 2, maxY < height - 2,
                      CGFloat(w) * sx >= 48, CGFloat(h) * sy >= 24,
                      Double(queue.count) / Double(w * h) >= 0.60 else { continue }
                let corners = [(minX + 1, minY + 1), (maxX - 1, minY + 1),
                               (minX + 1, maxY - 1), (maxX - 1, maxY - 1)]
                guard corners.allSatisfy({ labels[$0.1 * width + $0.0] != label }) else { continue }
                // Rounded surfaces have comparable cut-ins at all four corners.
                // A clipped surface, disconnected lines, or a square panel fails this check.
                func horizontalInset(y: Int) -> (Int, Int)? {
                    let xs = (minX...maxX).filter { labels[y * width + $0] == label }
                    guard let first = xs.first, let last = xs.last, xs.count >= w / 2 else { return nil }
                    return (first - minX, maxX - last)
                }
                func verticalInset(x: Int) -> (Int, Int)? {
                    let ys = (minY...maxY).filter { labels[$0 * width + x] == label }
                    guard let first = ys.first, let last = ys.last, ys.count >= h / 5 else { return nil }
                    return (first - minY, maxY - last)
                }
                guard let topInset = horizontalInset(y: minY + 1), let bottomInset = horizontalInset(y: maxY - 1),
                      let leftInset = verticalInset(x: minX + 1), let rightInset = verticalInset(x: maxX - 1) else { continue }
                let insets = [topInset.0, topInset.1, bottomInset.0, bottomInset.1,
                              leftInset.0, leftInset.1, rightInset.0, rightInset.1]
                let smallest = insets.min() ?? 0, largest = insets.max() ?? 0
                guard smallest >= 2, largest <= min(w, h) / 2,
                      Double(largest) <= Double(smallest) * 2.5 + 3 else { continue }
                let candidate = CGRect(x: CGFloat(minX) * sx, y: CGFloat(minY) * sy,
                                       width: CGFloat(w) * sx, height: CGFloat(h) * sy)
                if !regions.contains(where: { $0.intersection(candidate).width * $0.intersection(candidate).height > candidate.width * candidate.height * 0.9 }) {
                    regions.append(candidate)
                }
                if regions.count >= 24 { return regions }
            }
        }
        return regions
    }
}
