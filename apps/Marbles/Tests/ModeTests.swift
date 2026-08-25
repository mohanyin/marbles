import Foundation

enum ModeTests {
    @MainActor
    static func run() {
        let mode = ModeController()
        TestRun.expectEqual(mode.mode, .cluster)

        mode.hoverMarble("a")
        TestRun.expectEqual(mode.mode, .cluster, "Cluster hover does not unpack")

        mode.clickMarble("a")
        TestRun.expectEqual(mode.mode, .active, "cluster click goes to Active first")

        mode.hoverMarble("a")
        TestRun.expectEqual(mode.mode, .focus("a"), "Active hover opens Focus")

        mode.hoverMarble("b")
        TestRun.expectEqual(mode.mode, .focus("b"), "Focus hover switches agent")

        mode.hoverMarble("b")
        TestRun.expectEqual(mode.mode, .focus("b"), "Focus hover on hero stays")

        mode.clickMarble("b")
        TestRun.expectEqual(mode.mode, .active, "click hero leaves Focus")

        mode.hoverMarble("b")
        TestRun.expectEqual(mode.mode, .focus("b"), "Active hover reopens Focus")

        mode.escape()
        TestRun.expectEqual(mode.mode, .active, "Esc leaves Focus for Active")

        mode.escape()
        TestRun.expectEqual(mode.mode, .cluster, "Esc leaves Active for Cluster")

        mode.clickOverflow()
        TestRun.expectEqual(mode.mode, .active, "overflow click opens Active")

        mode.clickOutside()
        TestRun.expectEqual(mode.mode, .cluster, "outside click packs Active to Cluster")

        mode.clickMarble("a")
        mode.clickMarble("a")
        TestRun.expectEqual(mode.mode, .focus("a"))
        mode.clickOutside()
        TestRun.expectEqual(mode.mode, .cluster, "outside click packs Focus to Cluster")

        mode.clickMarble("a")
        mode.hoverMarble("a")
        TestRun.expectEqual(mode.mode, .focus("a"))
        mode.beginDrag()
        TestRun.expectEqual(mode.mode, .cluster, "drag collapses to Cluster")

        mode.escape()
        TestRun.expectEqual(mode.mode, .cluster, "Esc in Cluster is a no-op")
    }
}
