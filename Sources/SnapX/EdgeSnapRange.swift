import Foundation

enum EdgeSnapRange {
    static let defaultValue: Double = 16
    static let allowed: ClosedRange<Double> = 4...32
    static let preferenceKey = "experimentalEdgeSnappingRange"

    static func normalized(_ value: Double) -> Double {
        guard value.isFinite else { return defaultValue }
        return min(allowed.upperBound, max(allowed.lowerBound, value.rounded()))
    }

    static func load(from defaults: UserDefaults = .standard) -> Double {
        guard let value = defaults.object(forKey: preferenceKey) as? NSNumber else { return defaultValue }
        return normalized(value.doubleValue)
    }
}
