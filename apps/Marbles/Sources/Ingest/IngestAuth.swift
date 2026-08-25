import Foundation
import Security

enum IngestAuth {
    static let headerName = "X-Marbles-Token"
    static let minimumTokenLength = 32

    static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status == errSecSuccess {
            return bytes.map { String(format: "%02x", $0) }.joined()
        }
        return UUID().uuidString.replacingOccurrences(of: "-", with: "")
            + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }

    static func loadOrCreateToken(at url: URL) -> String {
        if let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let existing = json["token"] as? String,
           existing.count >= minimumTokenLength
        {
            return existing
        }
        return generateToken()
    }

    static func matches(_ provided: String?, secret: String) -> Bool {
        guard let provided, provided.count == secret.count, secret.count >= minimumTokenLength else {
            return false
        }
        let left = Array(provided.utf8)
        let right = Array(secret.utf8)
        guard left.count == right.count else { return false }
        var diff: UInt8 = 0
        for index in left.indices {
            diff |= left[index] ^ right[index]
        }
        return diff == 0
    }

    static func restrictFile(at url: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
