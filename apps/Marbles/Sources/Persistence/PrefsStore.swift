import Foundation

struct Prefs: Equatable, Codable {
    var version: Int = 1
    var reducedMotion: Bool = false
    var completionSound: Bool = false
    var satellites: Bool = true
    var launchAtLogin: Bool = false
    var overlayHidden: Bool = false
    var didFirstLaunch: Bool = false
    var demoOffered: Bool = false
    var pendingHookConfirmation: Bool = false
}

final class PrefsStore {
    static let shared = PrefsStore()

    private let url: URL
    private(set) var values: Prefs
    var onChange: (() -> Void)?

    init(url: URL = IngestConstants.prefsFileURL) {
        self.url = url
        self.values = PrefsStore.load(from: url)
    }

    func update(_ body: (inout Prefs) -> Void) {
        body(&values)
        save()
        onChange?()
    }

    private func save() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(values) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func load(from url: URL) -> Prefs {
        guard let data = try? Data(contentsOf: url),
              let prefs = try? JSONDecoder().decode(Prefs.self, from: data)
        else {
            return Prefs()
        }
        return prefs
    }
}
