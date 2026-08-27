import Foundation

enum ModeTests {
    @MainActor
    static func run() {
        let mode = ModeController()
        TestRun.expectEqual(mode.mode, .dock)

        mode.hoverMarble("a")
        TestRun.expectEqual(mode.mode, .focus("a"), "Default hover focuses")

        mode.hoverMarble("b")
        TestRun.expectEqual(mode.mode, .focus("b"), "hover switches agent")

        mode.hoverMarble("b")
        TestRun.expectEqual(mode.mode, .focus("b"), "hover on hero stays")

        mode.clickMarble("c")
        TestRun.expectEqual(mode.mode, .focus("c"), "click other marble switches")

        mode.clickMarble("c")
        TestRun.expectEqual(mode.mode, .focus("c"), "click focused marble stays")

        mode.escape()
        TestRun.expectEqual(mode.mode, .dock, "Esc leaves Focus for Default")

        mode.hoverMarble("a")
        TestRun.expectEqual(mode.mode, .focus("a"))
        mode.hoverOff()
        TestRun.expectEqual(mode.mode, .dock, "hover off dismisses Focus")

        mode.hoverMarble("a")
        mode.clickOutside()
        TestRun.expectEqual(mode.mode, .dock, "outside click dismisses Focus")

        mode.hoverMarble("a")
        mode.clickOutside()
        TestRun.expectEqual(mode.mode, .dock, "dock glass / outside dismisses")

        mode.escape()
        TestRun.expectEqual(mode.mode, .dock, "Esc in Default is a no-op")
    }
}
