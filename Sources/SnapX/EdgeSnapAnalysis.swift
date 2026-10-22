import CoreGraphics
import Foundation

/// Owns one cancellable worker per overlay. Late results cannot revive a closed gesture.
@MainActor
final class EdgeSnapAnalysis {
    private(set) var map: SnapEdgeMap?
    private(set) var isAnalyzing = false
    private var task: Task<Void, Never>?
    private var generation = UUID()
    var onUpdate: (() -> Void)?

    func start(size: CGSize, continuous: Bool, image: @escaping @Sendable () -> CGImage?) {
        stop()
        isAnalyzing = true
        let token = generation
        task = Task.detached(priority: .userInitiated) { [weak self] in
            repeat {
                guard !Task.isCancelled else { return }
                let map = image().map { SnapEdgeDetector.detect($0, logicalSize: size) }
                guard !Task.isCancelled else { return }
                await self?.accept(map, generation: token)
                guard continuous else { return }
                do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return }
            } while !Task.isCancelled
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        generation = UUID()
        map = nil
        isAnalyzing = false
    }

    private func accept(_ map: SnapEdgeMap?, generation: UUID) {
        guard self.generation == generation else { return }
        isAnalyzing = false
        self.map = map
        onUpdate?()
    }

    deinit { task?.cancel() }
}
