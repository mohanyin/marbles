import Foundation

struct SeedStore {
    private let url: URL

    init(url: URL = IngestConstants.seedsFileURL) {
        self.url = url
    }

    func seed(for sessionID: String) -> UInt64 {
        var seeds = load()
        if let hex = seeds[sessionID], let parsed = UInt64(hex, radix: 16) {
            return parsed
        }
        let value = FNV.hash64(sessionID)
        seeds[sessionID] = String(value, radix: 16)
        save(seeds)
        return value
    }

    func assign(_ seed: UInt64, to sessionID: String) {
        var seeds = load()
        seeds[sessionID] = String(seed, radix: 16)
        save(seeds)
    }

    private func load() -> [String: String] {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let seeds = json["seeds"] as? [String: String]
        else { return [:] }
        return seeds
    }

    private func save(_ seeds: [String: String]) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let payload: [String: Any] = ["version": 1, "seeds": seeds]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
