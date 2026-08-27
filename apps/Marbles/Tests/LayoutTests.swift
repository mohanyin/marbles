import AppKit
import Foundation

enum LayoutTests {
    static func run() {
        sizes()
        paddingAndStride()
        emptyDock()
        nineVisibleThenScroll()
        insertionOrderPacksOnLeave()
        noOverflowToken()
        snapOrientations()
        releaseAlwaysLocks()
        fourSnapOriginsAreDistinct()
        cornersMigrateToRight()
        focusKeepsMarbleSize()
        focusCardStaysOnScreen()
        focusCardIsCompact()
        dockStaysCenteredWhenCardOpens()
        scrollSnapsToItems()
        revealKeepsVisible()
        demoIsLaidOut()
    }

    private static func sizes() {
        let roster = agents(count: 3)
        let dock = dockLayout(roster)
        TestRun.expectEqual(dock.frames.count, 3, "dock frames")
        for frame in dock.frames.values {
            TestRun.expectNear(frame.size, LayoutEngine.marbleSize, "dock marble")
            TestRun.expectNear(frame.dim, 0, "no dim")
        }

        let heroID = roster[0].id
        let focus = dockLayout(roster, mode: .focus(heroID))
        TestRun.expectNear(focus.frames[heroID]?.size ?? 0, LayoutEngine.marbleSize, "focus marble stays 36")
        for frame in focus.frames.values {
            TestRun.expectNear(frame.size, LayoutEngine.marbleSize, "all marbles 36 in focus")
            TestRun.expectNear(frame.dim, 0, "no dim in focus")
        }
    }

    private static func paddingAndStride() {
        TestRun.expectNear(LayoutEngine.itemStride, 55, "36 + 4 + 3 + 12")
        let roster = agents(count: 2)
        let layout = dockLayout(roster)
        guard let a = layout.frames[roster[0].id], let b = layout.frames[roster[1].id] else {
            TestRun.expect(false, "expected two frames")
            return
        }
        TestRun.expectNear(abs(a.center.y - b.center.y), LayoutEngine.itemStride, "item stride")
        TestRun.expectEqual(layout.orientation.axis, .vertical, "default test dock is vertical")
        TestRun.expectNear(layout.dockFrame.width, LayoutEngine.occupiedThickness, "10 + 36 + 10")
        let marbleLeft = min(a.center.x, b.center.x) - LayoutEngine.marbleSize / 2
        TestRun.expectNear(marbleLeft - layout.dockFrame.minX, LayoutEngine.padding, "10pt side padding")
    }

    private static func emptyDock() {
        let layout = dockLayout([])
        TestRun.expectEqual(layout.frames.count, 0, "no marbles")
        TestRun.expectNear(layout.dockFrame.width, LayoutEngine.emptyThickness, "empty thickness")
        TestRun.expectNear(layout.dockFrame.height, LayoutEngine.emptyLength, "empty length")
    }

    private static func nineVisibleThenScroll() {
        let nine = dockLayout(agents(count: 9))
        TestRun.expectEqual(nine.visibleCount, 9, "nine fit")
        TestRun.expectNear(nine.maxScroll, 0, "no scroll at 9")
        TestRun.expectNear(nine.dockFrame.height, LayoutEngine.contentLength(count: 9), "dock grows to 9")

        let ten = dockLayout(agents(count: 10))
        TestRun.expectEqual(ten.visibleCount, 9, "cap visible at 9")
        TestRun.expectNear(ten.maxScroll, LayoutEngine.itemStride, "tenth requires one stride of scroll")
        TestRun.expectNear(ten.dockFrame.height, LayoutEngine.contentLength(count: 9), "viewport stays 9 tall")

        let scrolled = dockLayout(agents(count: 10), scrollOffset: LayoutEngine.itemStride)
        TestRun.expectNear(scrolled.scrollOffset, LayoutEngine.itemStride, "can scroll to last")
    }

    private static func insertionOrderPacksOnLeave() {
        var roster = agents(count: 4)
        let first = roster[0].id
        let sliding = roster[2].id
        roster.remove(at: 1)
        let packed = dockLayout(roster)
        TestRun.expectEqual(packed.frames.count, 3, "hole closed")
        guard let a = packed.frames[first], let b = packed.frames[sliding] else {
            TestRun.expect(false, "expected packed frames")
            return
        }
        TestRun.expectNear(abs(a.center.y - b.center.y), LayoutEngine.itemStride, "neighbors close the gap")
    }

    private static func noOverflowToken() {
        let layout = dockLayout(agents(count: 28))
        TestRun.expectEqual(layout.frames.count, 28, "all agents laid out")
        TestRun.expectEqual(layout.visibleCount, 9, "still 9 visible")
    }

    private static func snapOrientations() {
        TestRun.expectEqual(SnapGeometry.orientation(for: .left).axis, .vertical, "left vertical")
        TestRun.expectEqual(SnapGeometry.orientation(for: .right).axis, .vertical, "right vertical")
        TestRun.expectEqual(SnapGeometry.orientation(for: .top).axis, .horizontal, "top horizontal")
        TestRun.expectEqual(SnapGeometry.orientation(for: .bottom).axis, .horizontal, "bottom horizontal")
        TestRun.expectEqual(SnapPoint.allCases.count, 4, "four snap points")
        TestRun.expectEqual(SnapPoint.default, .right, "default is right")
    }

    private static func releaseAlwaysLocks() {
        let safe = NSRect(x: 12, y: 12, width: 1416, height: 876)
        let size = CGSize(width: 56, height: 176)
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

    private static func fourSnapOriginsAreDistinct() {
        let safe = NSRect(x: 12, y: 12, width: 1416, height: 876)
        let size = CGSize(width: 56, height: 176)
        let origins = SnapPoint.allCases.map { SnapGeometry.origin(for: $0, size: size, safe: safe) }
        let unique = Set(origins.map { "\($0.x),\($0.y)" })
        TestRun.expectEqual(unique.count, 4, "each snap point has its own origin")
    }

    private static func cornersMigrateToRight() {
        let data = try? JSONDecoder().decode(SnapPoint.self, from: Data("\"topLeft\"".utf8))
        TestRun.expectEqual(data, .right, "legacy corners migrate to right")
        let bottomRight = try? JSONDecoder().decode(SnapPoint.self, from: Data("\"bottomRight\"".utf8))
        TestRun.expectEqual(bottomRight, .right, "bottomRight migrates")
        let top = try? JSONDecoder().decode(SnapPoint.self, from: Data("\"top\"".utf8))
        TestRun.expectEqual(top, .top, "midpoints keep identity")
    }

    private static func focusKeepsMarbleSize() {
        let roster = agents(count: 3)
        let dock = dockLayout(roster)
        let focus = dockLayout(roster, mode: .focus(roster[1].id))
        TestRun.expectNear(dock.dockFrame.width, focus.dockFrame.width, "dock width unchanged")
        TestRun.expectNear(dock.dockFrame.height, focus.dockFrame.height, "dock height unchanged")
        TestRun.expect(focus.focusCardFrame != nil, "focus has a card")
        TestRun.expect(dock.focusCardFrame == nil, "dock has no card")
    }

    private static func focusCardStaysOnScreen() {
        let roster = agents(count: 3)
        let hero = roster[0].id
        let safe = NSRect(x: 12, y: 12, width: 1416, height: 876)
        for point in SnapPoint.allCases {
            let layout = LayoutEngine.layout(
                agents: roster,
                mode: .focus(hero),
                orientation: SnapGeometry.orientation(for: point),
                scrollOffset: 0,
                availableLineLength: point == .top || point == .bottom ? safe.width : safe.height,
                cardTowardPositivePerpendicular: SnapGeometry.cardTowardPositive(for: point)
            )
            guard let card = layout.focusCardFrame else {
                TestRun.expect(false, "focus card missing at \(point)")
                continue
            }
            let origin = SnapGeometry.panelOrigin(
                snap: .snap(point),
                dockFrame: layout.dockFrame,
                panelSize: layout.panelSize,
                safe: safe
            )
            let dockScreen = layout.dockFrame.offsetBy(dx: origin.x, dy: origin.y)
            let cardScreen = card.offsetBy(dx: origin.x, dy: origin.y)
            let expectedDock = SnapGeometry.origin(for: point, size: layout.dockFrame.size, safe: safe)
            TestRun.expectNear(dockScreen.minX, expectedDock.x, "\(point) dock stays at snap")
            TestRun.expectNear(dockScreen.minY, expectedDock.y, "\(point) dock y at snap")
            TestRun.expect(cardScreen.minX >= safe.minX - 0.5, "\(point) card left")
            TestRun.expect(cardScreen.maxX <= safe.maxX + 0.5, "\(point) card right")
        }
    }

    private static func focusCardIsCompact() {
        TestRun.expect(LayoutEngine.focusCardSize.width <= 360, "card ≤360pt")
        let roster = agents(count: 3)
        let focus = dockLayout(roster, mode: .focus(roster[0].id))
        TestRun.expect(focus.focusCardFrame != nil, "focus has a card")
        TestRun.expect(dockLayout(roster).focusCardFrame == nil, "dock has no card")
    }

    private static func dockStaysCenteredWhenCardOpens() {
        let roster = agents(count: 3)
        let dock = dockLayout(roster)
        let focus = dockLayout(roster, mode: .focus(roster[0].id))
        TestRun.expectNear(dock.dockFrame.width, focus.dockFrame.width, "pill width")
        TestRun.expectNear(dock.dockFrame.height, focus.dockFrame.height, "pill height")
    }

    private static func scrollSnapsToItems() {
        let snapped = LayoutEngine.snapScroll(LayoutEngine.itemStride * 0.6, maxScroll: LayoutEngine.itemStride * 4)
        TestRun.expectNear(snapped, LayoutEngine.itemStride, "round to nearest item")
        let clamped = LayoutEngine.snapScroll(10_000, maxScroll: LayoutEngine.itemStride)
        TestRun.expectNear(clamped, LayoutEngine.itemStride, "clamp then snap")
    }

    private static func revealKeepsVisible() {
        let current = LayoutEngine.scrollToReveal(index: 2, count: 12, available: 900, current: 0)
        TestRun.expectNear(current, 0, "already visible stays")
        let later = LayoutEngine.scrollToReveal(index: 11, count: 12, available: 900, current: 0)
        TestRun.expect(later > 0, "scroll to last item")
        TestRun.expectNear(
            later,
            LayoutEngine.scrollToReveal(index: 11, count: 12, available: 900, current: later),
            "idempotent once visible"
        )
    }

    private static func demoIsLaidOut() {
        let demo = DemoMarble.make()
        let layout = dockLayout([demo])
        TestRun.expectEqual(layout.frames.count, 1, "demo marble is visible")
    }
}
