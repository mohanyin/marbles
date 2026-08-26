import AppKit
import Foundation

protocol AppLaunching {
    func applicationExists(bundleID: String) -> Bool
    func runningBundleIDs() -> Set<String>
    func open(_ url: URL) throws
    func openApplication(bundleID: String) throws
    func open(_ folder: URL, bundleID: String) throws
}

enum JumpError: Error, Equatable {
    case appMissing
    case noWorkingDirectory
    case demo
    case failed
}

struct WorkspaceLauncher: AppLaunching {
    static let shared = WorkspaceLauncher()

    func applicationExists(bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    func runningBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    func open(_ url: URL) throws {
        guard NSWorkspace.shared.open(url) else { throw JumpError.failed }
    }

    func openApplication(bundleID: String) throws {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw JumpError.appMissing
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: app, configuration: config, completionHandler: nil)
    }

    func open(_ folder: URL, bundleID: String) throws {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw JumpError.appMissing
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([folder], withApplicationAt: app, configuration: config, completionHandler: nil)
    }
}
