import AppKit

enum CompletionSound {
    static func play() {
        NSSound(named: "Glass")?.play()
    }
}
