import Foundation

let timeout: TimeInterval = 0.15

struct IngestTarget {
    var url: URL
    var token: String?
}

func ingestTarget() -> IngestTarget {
    let file = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Marbles/ingest.json")
    if let data = try? Data(contentsOf: file),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    {
        let url = (json["url"] as? String).flatMap(URL.init(string:))
            ?? URL(string: "http://127.0.0.1:17832/hook")!
        let token = json["token"] as? String
        return IngestTarget(url: url, token: token)
    }
    return IngestTarget(url: URL(string: "http://127.0.0.1:17832/hook")!, token: nil)
}

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

let target = ingestTarget()
var request = URLRequest(url: target.url, timeoutInterval: timeout)
request.httpMethod = "POST"
request.setValue("application/json", forHTTPHeaderField: "Content-Type")
request.setValue("1", forHTTPHeaderField: "X-Marbles-Hook")
if let token = target.token, !token.isEmpty {
    request.setValue(token, forHTTPHeaderField: "X-Marbles-Token")
}
request.httpBody = body

let semaphore = DispatchSemaphore(value: 0)
URLSession.shared.dataTask(with: request) { _, _, error in
    if error != nil {
        debugLog("post failed")
    }
    semaphore.signal()
}.resume()

_ = semaphore.wait(timeout: .now() + timeout + 0.05)
exit(0)
