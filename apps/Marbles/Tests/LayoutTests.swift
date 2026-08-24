import AppKit
import Foundation

enum LayoutTests {
    static func run() {
        sizes()
        noOverflowAtCapacity()
        overflowAt28()
        overflowSitsInReservedSlot()
        stickySlotsDoNotRepack()
        lingerCountsTowardCap()
        activeShowsFullList()
        snapOrientations()
        releaseAlwaysLocks()
        eightSnapOriginsAreDistinct()
    }

    private static func sizes() {
        let roster = agents(count: 3)
        let cluster = clusterLayout(roster)
        TestRun.expectEqual(cluster.frames.count, 3, "cluster frames")
        for frame in cluster.frames.values {
            TestRun.expectNear(frame.size, LayoutEngine.clusterSize, "cluster marble")
        }

        let active = lineLayout(roster)
        TestRun.expectEqual(active.overflow, nil, "active has no overflow token")
        for frame in active.frames.values {
            TestRun.expectNear(frame.size, LayoutEngine.activeSize, "active marble")
        }

        let heroID = roster[0].id
        let focus = lineLayout(roster, mode: .focus(heroID))
        TestRun.expectNear(focus.frames[heroID]?.size ?? 0, LayoutEngine.focusHeroSize, "focus hero")
        for (id, frame) in focus.frames where id != heroID {
            TestRun.expectNear(frame.size, LayoutEngine.activeSize, "dimmed focus marble")
        }
    }

    private static func noOverflowAtCapacity() {
        let result = clusterLayout(agents(count: 27))
        TestRun.expectEqual(result.frames.count, 27, "full lattice")
        TestRun.expect(result.overflow == nil, "27 agents should not overflow")
        TestRun.expect(result.overflowFrame == nil, "no overflow frame at 27")
    }

    private static func overflowAt28() {
        let roster = agents(count: 28)
        let result = clusterLayout(roster)
        TestRun.expectEqual(result.frames.count, 26, "overflow shows 26 identities")
        TestRun.expectEqual(result.overflow?.hiddenCount, 2, "28 − 26 hidden")
        TestRun.expect(result.overflowFrame != nil, "overflow frame present")
        let occupyingOverflow = roster.contains { agent in
            agent.latticeIndex == LayoutEngine.overflowLatticeIndex && result.frames[agent.id] != nil
        }
        TestRun.expect(!occupyingOverflow, "reserved overflow slot stays free of an identity")
    }

    private static func overflowSitsInReservedSlot() {
        let roster = agents(count: 28)
        let result = clusterLayout(roster)
        guard let overflow = result.overflowFrame else {
            TestRun.expect(false, "expected overflow frame")
            return
        }
        guard let neighbor = roster.first(where: { result.frames[$0.id] != nil && $0.latticeIndex != nil }),
              let neighborIndex = neighbor.latticeIndex,
              let neighborFrame = result.frames[neighbor.id]
        else {
            TestRun.expect(false, "expected a visible neighbor")
            return
        }
        let expected = LayoutEngine.latticeCenter(index: LayoutEngine.overflowLatticeIndex)
        let neighborCenter = LayoutEngine.latticeCenter(index: neighborIndex)
        TestRun.expectNear(
            overflow.center.x - neighborFrame.center.x,
            expected.x - neighborCenter.x,
            "overflow x in lattice"
        )
        TestRun.expectNear(
            overflow.center.y - neighborFrame.center.y,
            expected.y - neighborCenter.y,
            "overflow y in lattice"
        )
        TestRun.expectNear(overflow.size, LayoutEngine.clusterSize, "overflow size")
        TestRun.expectEqual(
            LayoutEngine.latticeCoordinate(index: LayoutEngine.overflowLatticeIndex).x, 2
        )
        TestRun.expectEqual(
            LayoutEngine.latticeCoordinate(index: LayoutEngine.overflowLatticeIndex).y, 0
        )
        TestRun.expectEqual(
            LayoutEngine.latticeCoordinate(index: LayoutEngine.overflowLatticeIndex).z, 0
        )
    }

    private static func stickySlotsDoNotRepack() {
        var roster = agents(count: 5)
        let original = Dictionary(uniqueKeysWithValues: roster.map { ($0.id, $0.latticeIndex) })
        roster.removeAll { $0.latticeIndex == 1 }
        let incoming = Agent.debugDummy(index: 99)
        roster.append(incoming)
        LatticeSlots.assign(&roster)
        for agent in roster where agent.id != incoming.id {
            TestRun.expectEqual(agent.latticeIndex, original[agent.id], "slot stayed for \(agent.id)")
        }
        TestRun.expectEqual(roster.last?.latticeIndex, 1, "new agent reuses vacated slot")

        let sparse: [Agent] = [0, 8, 20].map { index in
            var agent = Agent.debugDummy(index: index)
            agent.latticeIndex = index
            return agent
        }
        let result = clusterLayout(sparse)
        TestRun.expectEqual(result.frames.count, 3)
        let centers = sparse.compactMap { agent -> CGPoint? in
            result.frames[agent.id].map(\.center)
        }
        TestRun.expectEqual(Set(centers.map { "\($0.x),\($0.y)" }).count, 3, "sparse slots stay unpacked")
        if let a = result.frames[sparse[0].id], let b = result.frames[sparse[1].id] {
            let expected = LayoutEngine.latticeCenter(index: 8)
            let origin = LayoutEngine.latticeCenter(index: 0)
            TestRun.expectNear(b.center.x - a.center.x, expected.x - origin.x, "sticky x")
            TestRun.expectNear(b.center.y - a.center.y, expected.y - origin.y, "sticky y")
        }
    }

    private static func lingerCountsTowardCap() {
        var roster = agents(count: 26)
        for i in 0..<2 {
            var lingered = Agent.debugDummy(index: 80 + i)
            lingered.sessionEndedAt = Date()
            roster.append(lingered)
        }
        LatticeSlots.assign(&roster)
        let result = clusterLayout(roster)
        TestRun.expectEqual(result.frames.count, 26, "linger still occupies cluster capacity")
        TestRun.expectEqual(result.overflow?.hiddenCount, 2, "linger counts toward overflow")
    }

    private static func activeShowsFullList() {
        let roster = agents(count: 28)
        let result = lineLayout(roster)
        TestRun.expectEqual(result.frames.count, 28, "Active shows every agent, including overflowed")
        TestRun.expect(result.overflow == nil, "Active does not draw a +N token")
    }

    private static func snapOrientations() {
        for point in [SnapPoint.topLeft, .topRight, .bottomLeft, .bottomRight, .left, .right] {
            let orientation = SnapGeometry.orientation(for: point)
            TestRun.expectEqual(orientation.axis, .vertical, "\(point) should be vertical")
        }
        TestRun.expectEqual(SnapGeometry.orientation(for: .top).axis, .horizontal, "top midpoint")
        TestRun.expectEqual(SnapGeometry.orientation(for: .bottom).axis, .horizontal, "bottom midpoint")
        TestRun.expectEqual(SnapPoint.allCases.count, 8, "eight snap points")
    }

    private static func releaseAlwaysLocks() {
        let safe = NSRect(x: 12, y: 12, width: 1416, height: 876)
        let size = CGSize(width: 52, height: 52)
        for point in SnapPoint.allCases {
            let origin = SnapGeometry.origin(for: point, size: size, safe: safe)
            let resolved = SnapGeometry.resolveRelease(
                panelFrame: NSRect(origin: origin, size: size),
                safe: safe
            )
            TestRun.expectEqual(resolved, .snap(point), "exact \(point) release")
        }

        let mid = SnapGeometry.resolveRelease(
            panelFrame: NSRect(x: 700, y: 400, width: size.width, height: size.height),
            safe: safe
        )
        if case .snap = mid {
            // locked to a snap point, not free-place
        } else {
            TestRun.expect(false, "mid-screen release must still snap, got \(mid)")
        }
    }

    private static func eightSnapOriginsAreDistinct() {
        let safe = NSRect(x: 12, y: 12, width: 1416, height: 876)
        let size = CGSize(width: 52, height: 52)
        let origins = SnapPoint.allCases.map { SnapGeometry.origin(for: $0, size: size, safe: safe) }
        let unique = Set(origins.map { "\($0.x),\($0.y)" })
        TestRun.expectEqual(unique.count, 8, "each snap point has its own origin")
    }
}
