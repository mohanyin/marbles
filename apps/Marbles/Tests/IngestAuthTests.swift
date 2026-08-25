import Foundation

enum IngestAuthTests {
    static func run() {
        generateIsLongEnough()
        matchAcceptsExact()
        matchRejectsMissingWrongAndShort()
        loadReusesExisting()
        loadCreatesWhenMissing()
    }

    private static func generateIsLongEnough() {
        let token = IngestAuth.generateToken()
        TestRun.expect(token.count >= IngestAuth.minimumTokenLength, "generated token length")
        TestRun.expect(token.allSatisfy { $0.isHexDigit }, "token is hex")
    }

    private static func matchAcceptsExact() {
        let token = IngestAuth.generateToken()
        TestRun.expect(IngestAuth.matches(token, secret: token), "exact match")
    }

    private static func matchRejectsMissingWrongAndShort() {
        let token = IngestAuth.generateToken()
        TestRun.expect(!IngestAuth.matches(nil, secret: token), "missing header")
        TestRun.expect(!IngestAuth.matches("", secret: token), "empty header")
        TestRun.expect(!IngestAuth.matches("abc", secret: token), "short header")
        var wrong = Array(token)
        wrong[0] = wrong[0] == Character("a") ? "b" : "a"
        TestRun.expect(!IngestAuth.matches(String(wrong), secret: token), "wrong token")
        TestRun.expect(!IngestAuth.matches(token, secret: "tooshort"), "short secret")
    }

    private static func loadReusesExisting() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ingest-\(UUID().uuidString).json")
        let existing = IngestAuth.generateToken()
        let payload = ["url": "http://127.0.0.1:17832/hook", "token": existing]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        try! data.write(to: url)
        TestRun.expectEqual(IngestAuth.loadOrCreateToken(at: url), existing)
        try? FileManager.default.removeItem(at: url)
    }

    private static func loadCreatesWhenMissing() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ingest-missing-\(UUID().uuidString).json")
        let created = IngestAuth.loadOrCreateToken(at: url)
        TestRun.expect(created.count >= IngestAuth.minimumTokenLength, "created token")
        try? FileManager.default.removeItem(at: url)
    }
}
