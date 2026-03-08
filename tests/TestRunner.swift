import Foundation

@main
enum TestRunner {
    static func main() {
        runNotificationGeometryTests()
        runDisplayPositionStoreTests()

        if failCount > 0 {
            print("\n\(failCount)/\(testCount) assertions FAILED")
            exit(1)
        } else {
            print("\nAll \(testCount) assertions passed.")
        }
    }
}
