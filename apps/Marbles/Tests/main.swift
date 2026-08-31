import Foundation

@main
@MainActor
struct MarblesTestRunner {
    static func main() {
        LayoutTests.run()
        ModeTests.run()
        StatusTests.run()
        HookMapperTests.run()
        IngestAuthTests.run()
        MotionTests.run()
        IdentityTests.run()
        FocusPreviewTests.run()
        FocusCardMetricsTests.run()
        TranscriptTests.run()
        MarkdownTests.run()
        HooksMergeTests.run()
        DemoTests.run()
        if TestRun.failures > 0 {
            print("\(TestRun.failures) test(s) failed")
            exit(1)
        }
        print("All tests passed")
    }
}
