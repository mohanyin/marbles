import Foundation

enum IngestConstants {
    static let defaultPort = 17_832
    static let supportDirectoryName = "Marbles"
    static let ingestFileName = "ingest.json"
    static let seedsFileName = "seeds.json"
    static let linger: TimeInterval = 45

    static var applicationSupport: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return root.appendingPathComponent(supportDirectoryName, isDirectory: true)
    }

    static var ingestFileURL: URL {
        applicationSupport.appendingPathComponent(ingestFileName)
    }

    static var seedsFileURL: URL {
        applicationSupport.appendingPathComponent(seedsFileName)
    }

    static func defaultURL(port: Int = defaultPort) -> URL {
        URL(string: "http://127.0.0.1:\(port)/hook")!
    }
}
