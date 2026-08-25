import Foundation

enum FixtureFiles {
    static func hooksDirectory(startingAt filePath: String) -> URL? {
        var directory = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = directory.appendingPathComponent("Tests/Fixtures/hooks")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            directory.deleteLastPathComponent()
        }
        return nil
    }

    static func data(named name: String, startingAt filePath: String) -> Data? {
        let file = name.hasSuffix(".json") ? name : "\(name).json"
        guard let directory = hooksDirectory(startingAt: filePath) else { return nil }
        return try? Data(contentsOf: directory.appendingPathComponent(file))
    }
}
