import Foundation

let timeout: TimeInterval = 0.15

func debugLog(_ message: String) {
    guard ProcessInfo.processInfo.environment["MARBLES_HOOK_DEBUG"] == "1" else { return }
    let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Marbles", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let line = String((Date().description + " " + message).prefix(2048)) + "\n"
    let url = directory.appendingPathComponent("hook.log")
    if let handle = try? FileHandle(forWritingTo: url) {
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        if let data = line.data(using: .utf8) {
            try? handle.write(contentsOf: data)
        }
    } else {
        try? line.data(using: .utf8)?.write(to: url)
    }
}

var body = FileHandle.standardInput.readDataToEndOfFile()
if body.isEmpty || (try? JSONSerialization.jsonObject(with: body)) == nil {
    body = Data(#"{"parseError":true}"#.utf8)
}

let target = IngestConstants.loadPublishedTarget()
let request = IngestAuth.hookRequest(url: target.url, body: body, token: target.token, timeout: timeout)

let semaphore = DispatchSemaphore(value: 0)
URLSession.shared.dataTask(with: request) { _, _, error in
    if error != nil {
        debugLog("post failed")
    }
    semaphore.signal()
}.resume()

_ = semaphore.wait(timeout: .now() + timeout + 0.05)
exit(0)
