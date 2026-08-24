import Foundation

@main
@MainActor
struct MarblesTestRunner {
    static func main() {
        LayoutTests.run()
        ModeTests.run()
        if TestRun.failures > 0 {
            print("\(TestRun.failures) test(s) failed")
            exit(1)
        }
        print("All tests passed")
    }
}
