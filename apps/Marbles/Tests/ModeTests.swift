import Foundation

enum ModeTests {
    @MainActor
    static func run() {
        let mode = ModeController()
        TestRun.expectEqual(mode.mode, .cluster)

        mode.clickMarble("a")
        TestRun.expectEqual(mode.mode, .active, "cluster click goes to Active first")

        mode.clickMarble("a")
        TestRun.expectEqual(mode.mode, .focus("a"))

        mode.clickMarble("b")
        TestRun.expectEqual(mode.mode, .focus("b"), "click another marble switches Focus")

        mode.escape()
        TestRun.expectEqual(mode.mode, .active, "Esc leaves Focus for Active")

        mode.escape()
        TestRun.expectEqual(mode.mode, .cluster, "Esc leaves Active for Cluster")

        mode.clickOverflow()
        TestRun.expectEqual(mode.mode, .active, "overflow click opens Active")

        mode.clickMarble("a")
        mode.clickOutside()
        TestRun.expectEqual(mode.mode, .cluster, "outside click packs to Cluster")

        mode.clickMarble("a")
        mode.clickMarble("a")
        mode.beginDrag()
        TestRun.expectEqual(mode.mode, .cluster, "drag collapses to Cluster")

        mode.escape()
        TestRun.expectEqual(mode.mode, .cluster, "Esc in Cluster is a no-op")
    }
}
