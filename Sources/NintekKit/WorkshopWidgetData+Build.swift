import Foundation

/// Flattens the live `WSProject` list (as loaded by the Dashboard) into the
/// compact shape the widgets read — kept separate from `WorkshopWidgetData.swift`
/// so the snapshot type itself stays free of any dependency on the fuller
/// project model.
public extension WorkshopWidgetSnapshot {
    init(projects: [WSProject], maxInProgress: Int = 5) {
        let inProgress = projects.filter { $0.status == .inProgress }
        let inQueue = projects.filter { $0.status == .idea || $0.status == .planning }
        let active = projects.filter { $0.status != .completed }
        self.init(
            signedIn: true,
            inProgressCount: inProgress.count,
            inQueueCount: inQueue.count,
            totalParts: active.reduce(0) { $0 + ($1.partsCount ?? 0) },
            totalValue: active.reduce(0.0) { $0 + ($1.totalCost ?? 0) },
            inProgress: inProgress.prefix(maxInProgress).map {
                InProgressProject(id: $0.id, title: $0.title, partsCount: $0.partsCount ?? 0, difficulty: $0.difficulty.rawValue)
            },
            updatedAt: Date()
        )
    }
}
