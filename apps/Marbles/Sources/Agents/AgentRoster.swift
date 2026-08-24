import Foundation

/// W1 stand-in for AgentStore. W2 replaces mutation with hook events.
@MainActor
final class AgentRoster {
    private(set) var agents: [Agent] = []

    func replaceWithDebugDummies(count: Int) {
        var next: [Agent] = (0..<count).map { Agent.debugDummy(index: $0) }
        LatticeSlots.assign(&next)
        agents = next
    }

    func clear() {
        agents = []
    }

    func agent(id: AgentID) -> Agent? {
        agents.first { $0.id == id }
    }

    func setStatus(_ status: AgentStatus, for id: AgentID) {
        guard let index = agents.firstIndex(where: { $0.id == id }) else { return }
        agents[index].status = status
        agents[index].lastEventAt = Date()
    }

    func cycleTool(for id: AgentID) {
        let names = ["Read", "Edit", "Bash", "Grep", "Task"]
        guard let index = agents.firstIndex(where: { $0.id == id }) else { return }
        let current = agents[index].currentTool?.name ?? names.last!
        let nextName = names[((names.firstIndex(of: current) ?? -1) + 1) % names.count]
        agents[index].currentTool = ToolEvent(
            id: UUID().uuidString,
            name: nextName,
            fileHint: "Example.swift",
            phase: .started,
            at: Date()
        )
        agents[index].status = .working
        agents[index].lastEventAt = Date()
    }

}

enum LatticeSlots {
    static func assign(_ agents: inout [Agent]) {
        var used = Set<Int>()
        for i in agents.indices {
            if let existing = agents[i].latticeIndex, existing >= 0, existing <= 26, !used.contains(existing) {
                used.insert(existing)
                continue
            }
            let slot = (0...26).first { !used.contains($0) }
            agents[i].latticeIndex = slot
            if let slot { used.insert(slot) }
        }
    }
}
