import Foundation

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
