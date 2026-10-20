import Foundation

/// Keeps navigation independent from batch selection and preserves a nearby item after deletion.
struct HistorySelection {
    var focusedID: UUID?
    var selectedIDs: Set<UUID> = []
    private var anchorID: UUID?
    private var previousIDs: [UUID] = []

    mutating func reconcile(_ ids: [UUID]) {
        let oldIndex = focusedID.flatMap { previousIDs.firstIndex(of: $0) } ?? 0
        selectedIDs.formIntersection(ids)
        if focusedID == nil || !ids.contains(focusedID!) {
            focusedID = ids.isEmpty ? nil : ids[min(oldIndex, ids.count - 1)]
            if selectedIDs.isEmpty, let focusedID { selectedIDs = [focusedID] }
        }
        if anchorID == nil || !ids.contains(anchorID!) { anchorID = focusedID }
        previousIDs = ids
    }

    mutating func select(_ id: UUID, in ids: [UUID], command: Bool = false, shift: Bool = false) {
        guard let index = ids.firstIndex(of: id) else { return }
        if shift, let anchorID, let anchor = ids.firstIndex(of: anchorID) {
            let range = Set(ids[min(anchor, index)...max(anchor, index)])
            selectedIDs = command ? selectedIDs.union(range) : range
        } else if command {
            if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
            anchorID = id
        } else {
            selectedIDs = [id]
            anchorID = id
        }
        focusedID = id
        previousIDs = ids
    }

    mutating func move(_ delta: Int, in ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let index = focusedID.flatMap { ids.firstIndex(of: $0) } ?? 0
        let next = ids[min(max(index + delta, 0), ids.count - 1)]
        if selectedIDs.count > 1 { focusedID = next } else { select(next, in: ids) }
    }
}
