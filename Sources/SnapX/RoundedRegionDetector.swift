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
        queue.reserveCapacity(4096)
        var regions: [CGRect] = []
        var label: UInt16 = 0

        return pixels.withUnsafeBufferPointer { pixelBuf -> [CGRect] in
            guard let pxPtr = pixelBuf.baseAddress else { return [] }
            return labels.withUnsafeMutableBufferPointer { labelBuf -> [CGRect] in
                guard let lblPtr = labelBuf.baseAddress else { return [] }

                @inline(__always)
                func tryEnqueue(_ next: Int, red: Int, green: Int, blue: Int, colorTolerance: Int, label: UInt16) {
                    guard lblPtr[next] == 0 else { return }
                    let offset = next * 4
                    if abs(Int(pxPtr[offset]) - red) <= colorTolerance &&
                        abs(Int(pxPtr[offset + 1]) - green) <= colorTolerance &&
                        abs(Int(pxPtr[offset + 2]) - blue) <= colorTolerance {
                        lblPtr[next] = label
                        queue.append(Int32(next))
                    }
                }

                for edge in seeds {
                    if Task.isCancelled { return [] }
                    let x = min(width - 1, max(0, Int((edge.start + edge.end) / (2 * sx))))
                    let y = Int(edge.position / sy)
                    let top = max(0, y - 3), bottom = min(height - 1, y + 3)
                    let a = (top * width + x) * 4, b = (bottom * width + x) * 4
                    let contrast = max(
                        abs(Int(pxPtr[a]) - Int(pxPtr[b])),
                        max(abs(Int(pxPtr[a + 1]) - Int(pxPtr[b + 1])),
                            abs(Int(pxPtr[a + 2]) - Int(pxPtr[b + 2])))
                    )
                    guard contrast >= 8 else { continue }
                    let colorTolerance = max(3, min(10, Int(Double(contrast) * 0.35)))
                    for seedY in [top, bottom] {
                        let seed = seedY * width + x
                        guard lblPtr[seed] == 0 else { continue }
                        label += 1
                        let seedOffset = seed * 4
                        let red = Int(pxPtr[seedOffset]), green = Int(pxPtr[seedOffset + 1]), blue = Int(pxPtr[seedOffset + 2])
                        queue.removeAll(keepingCapacity: true)
                        queue.append(Int32(seed))
                        lblPtr[seed] = label
                        var head = 0, minX = x, maxX = x, minY = seedY, maxY = seedY
                        while head < queue.count {
                            if head & 4095 == 0 && Task.isCancelled { return [] }
                            // The raster is capped at 2048 per side and each pixel is
                            // visited once. Finish large backgrounds so later bubbles are not skipped.
                            let index = Int(queue[head]); head += 1
                            let px = index % width, py = index / width
                            if px < minX { minX = px }
                            if px > maxX { maxX = px }
                            if py < minY { minY = py }
                            if py > maxY { maxY = py }
                            if px > 0 { tryEnqueue(index - 1, red: red, green: green, blue: blue, colorTolerance: colorTolerance, label: label) }
                            if px + 1 < width { tryEnqueue(index + 1, red: red, green: green, blue: blue, colorTolerance: colorTolerance, label: label) }
                            if py > 0 { tryEnqueue(index - width, red: red, green: green, blue: blue, colorTolerance: colorTolerance, label: label) }
                            if py + 1 < height { tryEnqueue(index + width, red: red, green: green, blue: blue, colorTolerance: colorTolerance, label: label) }
                        }
                        let w = maxX - minX + 1, h = maxY - minY + 1
                        guard minX > 1, minY > 1, maxX < width - 2, maxY < height - 2,
                              CGFloat(w) * sx >= 48, CGFloat(h) * sy >= 24,
                              Double(queue.count) / Double(w * h) >= 0.60 else { continue }
                        guard lblPtr[(minY + 1) * width + (minX + 1)] != label,
                              lblPtr[(minY + 1) * width + (maxX - 1)] != label,
                              lblPtr[(maxY - 1) * width + (minX + 1)] != label,
                              lblPtr[(maxY - 1) * width + (maxX - 1)] != label else { continue }
                        // Rounded surfaces have comparable cut-ins at all four corners.
                        // A clipped surface, disconnected lines, or a square panel fails this check.
                        func horizontalInset(y: Int) -> (Int, Int)? {
                            let rowStart = y * width
                            var first = -1, last = -1, count = 0
                            for cx in minX...maxX where lblPtr[rowStart + cx] == label {
                                if first < 0 { first = cx }
                                last = cx
                                count += 1
                            }
                            guard first >= 0, count >= w / 2 else { return nil }
                            return (first - minX, maxX - last)
                        }
                        func verticalInset(x: Int) -> (Int, Int)? {
                            var first = -1, last = -1, count = 0
                            for cy in minY...maxY where lblPtr[cy * width + x] == label {
                                if first < 0 { first = cy }
                                last = cy
                                count += 1
                            }
                            guard first >= 0, count >= h / 5 else { return nil }
                            return (first - minY, maxY - last)
                        }
                        guard let topInset = horizontalInset(y: minY + 1), let bottomInset = horizontalInset(y: maxY - 1),
                              let leftInset = verticalInset(x: minX + 1), let rightInset = verticalInset(x: maxX - 1) else { continue }
                        let smallest = min(min(topInset.0, topInset.1), min(min(bottomInset.0, bottomInset.1), min(min(leftInset.0, leftInset.1), min(rightInset.0, rightInset.1))))
                        let largest = max(max(topInset.0, topInset.1), max(max(bottomInset.0, bottomInset.1), max(max(leftInset.0, leftInset.1), max(rightInset.0, rightInset.1))))
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
    }
}
