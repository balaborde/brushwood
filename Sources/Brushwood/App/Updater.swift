import AppKit
import BrushwoodCore
import CryptoKit

extension AppVersion {
    /// The running app's version (nil when not running from an app bundle, e.g. `swift run`).
    static var current: AppVersion? {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(AppVersion.init)
    }
}

/// The latest published release, as listed on GitHub.
struct Release {
    let version: AppVersion
    let notes: String
    let page: URL
    let dmg: URL?
    /// SHA-256 of the disk image in hex, when GitHub provides it.
    let sha256: String?
}

/// Reads the latest release from GitHub. `BRUSHWOOD_UPDATE_FEED` points elsewhere for testing (a file:// URL works).
enum UpdateFeed {
    static let url = URL(string: ProcessInfo.processInfo.environment["BRUSHWOOD_UPDATE_FEED"]
        ?? "https://api.github.com/repos/balaborde/brushwood/releases/latest")!

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: URL
            let digest: String?
        }
        let tagName: String
        let htmlUrl: URL
        let body: String?
        let assets: [Asset]
    }

    static func fetch(_ completion: @escaping (Result<Release, Error>) -> Void) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, response, error in
            let result = Result<Release, Error> {
                if let error { throw error }
                if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw URLError(.badServerResponse) }
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let r = try decoder.decode(GitHubRelease.self, from: data ?? Data())
                guard let version = AppVersion(r.tagName) else { throw URLError(.cannotParseResponse) }
                let dmg = r.assets.first { $0.name.lowercased().hasSuffix(".dmg") }
                let sha = dmg?.digest.flatMap { $0.hasPrefix("sha256:") ? String($0.dropFirst(7)) : nil }
                return Release(version: version, notes: r.body ?? "", page: r.htmlUrl, dmg: dmg?.browserDownloadUrl, sha256: sha)
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }
}

/// Downloads the disk image, reporting progress on the main thread.
final class UpdateDownload: NSObject, URLSessionDownloadDelegate {
    private var session: URLSession!
    private let progress: (Int64, Int64) -> Void
    private let completion: (Result<URL, Error>) -> Void
    private var finished = false

    init(url: URL, progress: @escaping (Int64, Int64) -> Void, completion: @escaping (Result<URL, Error>) -> Void) {
        self.progress = progress
        self.completion = completion
        super.init()
        session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: .main)
        session.downloadTask(with: url).resume()
    }

    func cancel() { session.invalidateAndCancel() }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
            finish(.failure(URLError(.badServerResponse)))
            return
        }
        // The file at `location` is deleted when this method returns.
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("Brushwood-update-\(UUID().uuidString).dmg")
        do {
            try FileManager.default.moveItem(at: location, to: file)
            finish(.success(file))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard !finished else { return }
        finished = true
        session.finishTasksAndInvalidate()
        completion(result)
    }
}

/// Replaces the running app with the one in a downloaded disk image. Runs off the main thread.
enum UpdateInstaller {
    enum Failure: Error {
        /// The file does not match GitHub's checksum, does not mount, or does not hold the expected Brushwood.
        case damaged
        /// Brushwood runs from a read-only place (the disk image, or a quarantined copy macOS moved aside).
        case notInstalled
        /// The folder holding Brushwood cannot be written to (for example /Applications for a standard user).
        case notWritable
    }

    static func install(dmg: URL, release: Release) throws {
        defer { try? FileManager.default.removeItem(at: dmg) }
        let current = Bundle.main.bundleURL
        let readOnly = (try? current.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? false
        if readOnly || current.path.contains("/AppTranslocation/") { throw Failure.notInstalled }

        if let sha = release.sha256 {
            let data = try Data(contentsOf: dmg, options: .mappedIfSafe)
            let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard hex == sha.lowercased() else { throw Failure.damaged }
        }

        let fm = FileManager.default
        let mount = fm.temporaryDirectory.appendingPathComponent("Brushwood-update-\(UUID().uuidString)")
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: mount) }
        guard run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path]) else {
            throw Failure.damaged
        }
        defer { run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }

        // The disk image must hold this app (same identifier) at the advertised version, with an intact signature.
        guard let app = try fm.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "app" }),
              let bundle = Bundle(url: app), bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              let version = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(AppVersion.init),
              version == release.version,
              run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]) else { throw Failure.damaged }

        // Copy next to the current app (same volume), then swap the two in one step.
        let staging = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: current, create: true)
        defer { try? fm.removeItem(at: staging) }
        let staged = staging.appendingPathComponent(current.lastPathComponent)
        guard run("/usr/bin/ditto", [app.path, staged.path]) else { throw Failure.damaged }
        do {
            _ = try fm.replaceItemAt(current, withItemAt: staged)
        } catch {
            throw Failure.notWritable
        }
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = arguments
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}

/// Brushwood › Check for Updates…: finds a newer release on GitHub, then downloads and installs it.
final class UpdateController {
    static let shared = UpdateController()
    static let automaticKey = "checkForUpdatesAutomatically"
    private static let lastCheckKey = "lastUpdateCheck"

    private var window: UpdateWindow?
    private var download: UpdateDownload?
    private var checking = false

    /// Checks right away and shows the result, including "up to date" and errors.
    func checkNow() {
        showWindow().show(.checking)
        check(silent: false)
    }

    /// At launch: checks at most once a day, if enabled in Settings, and only speaks up when there is an update.
    func checkInBackgroundIfDue() {
        let d = UserDefaults.standard
        guard d.bool(forKey: Self.automaticKey) else { return }
        if let last = d.object(forKey: Self.lastCheckKey) as? Date, Date().timeIntervalSince(last) < 24 * 3600 { return }
        check(silent: true)
    }

    private func check(silent: Bool) {
        guard !checking else { return }
        checking = true
        UpdateFeed.fetch { [weak self] result in
            guard let self else { return }
            checking = false
            switch result {
            case .success(let release):
                UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
                if let current = AppVersion.current, current < release.version {
                    showWindow().show(.available(release))
                } else if !silent {
                    window?.show(.upToDate)
                }
            case .failure:
                if !silent { window?.show(.checkFailed) }
            }
        }
    }

    private func showWindow() -> UpdateWindow {
        let w = window ?? UpdateWindow()
        if window == nil {
            window = w
            w.center()
            w.onInstall = { [weak self] release in self?.install(release) }
            w.onCancel = { [weak self] in
                self?.download?.cancel()
                self?.download = nil
            }
        }
        w.makeKeyAndOrderFront(nil)
        return w
    }

    private func install(_ release: Release) {
        guard let url = release.dmg else {
            window?.show(.installFailed(L("No download is available for this version yet."), release))
            return
        }
        window?.show(.downloading(release, 0, 0))
        download = UpdateDownload(url: url, progress: { [weak self] done, total in
            self?.window?.show(.downloading(release, done, total))
        }, completion: { [weak self] result in
            guard let self else { return }
            download = nil
            switch result {
            case .success(let file):
                window?.show(.installing(release))
                DispatchQueue.global(qos: .userInitiated).async {
                    let outcome = Result { try UpdateInstaller.install(dmg: file, release: release) }
                    DispatchQueue.main.async { self.finishInstall(outcome, release) }
                }
            case .failure(let error):
                if (error as? URLError)?.code == .cancelled { return }
                window?.show(.installFailed(L("Check your internet connection and try again."), release))
            }
        })
    }

    private func finishInstall(_ outcome: Result<Void, Error>, _ release: Release) {
        switch outcome {
        case .success:
            relaunchApp()
        case .failure(let error):
            let message: String
            switch error as? UpdateInstaller.Failure {
            case .notInstalled?:
                message = L("Brushwood is running from the disk image or the Downloads folder. Move it to the Applications folder, then try again.")
            case .notWritable?:
                message = L("Brushwood cannot replace itself in its current folder. Download the new version from GitHub and install it by hand.")
            default:
                message = L("The downloaded file is damaged. Try again later.")
            }
            window?.show(.installFailed(message, release))
        }
    }
}
