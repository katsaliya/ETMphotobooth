import Combine
import Foundation
import Network
import Security

// MARK: - Feature flags

enum BoothFeatures {
    /// TEXTING_ENABLED — texting is on hold; screen 04 shows a QR code
    /// instead. The texting UI (keypad, consent, Sent) stays in the code
    /// behind this flag. Don't turn it on until DeliveryService texting is real.
    static let textingEnabled = false
}

// MARK: - Config (BoothDelivery.plist, not in git)

/// Photo page address + booth key, read from `BoothDelivery.plist` in the
/// app bundle. That file is git-ignored; copy
/// `RecieptPhotoBooth/BoothDelivery.example.plist` next to the Swift files
/// and fill it in. Without it the QR panel says the link isn't set up.
nonisolated struct DeliveryConfig: Sendable {
    /// e.g. https://etm-photobooth.<account>.workers.dev — no trailing slash.
    /// Switch to https://photos.<our domain> later by changing the plist.
    let baseURL: URL
    /// Same value as the Worker secret BOOTH_KEY.
    let boothKey: String

    static let shared: DeliveryConfig? = {
        guard let url = Bundle.main.url(forResource: "BoothDelivery", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let base = (dict["BASE_URL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let baseURL = URL(string: base.hasSuffix("/") ? String(base.dropLast()) : base),
              let key = dict["BOOTH_KEY"] as? String, !key.isEmpty, !key.hasPrefix("REPLACE")
        else { return nil }
        return DeliveryConfig(baseURL: baseURL, boothKey: key)
    }()

    func photoPageURL(for sessionID: String) -> URL {
        baseURL.appendingPathComponent("p").appendingPathComponent(sessionID)
    }

    func uploadURL(for sessionID: String, file: SessionFile) -> URL {
        baseURL.appendingPathComponent("api/upload")
            .appendingPathComponent(sessionID)
            .appendingPathComponent(file.rawValue)
    }
}

// MARK: - Session IDs

/// 7 base36 chars of the creation time + 16 random URL-safe chars (23 total).
/// The random part makes the link unguessable; the time prefix lets the
/// photo page tell "still uploading" from "expired" without a database.
/// Must match ID_PATTERN in photo-page/src/index.ts.
nonisolated enum SessionID {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

    static func make(now: Date = Date()) -> String {
        let seconds = String(Int(now.timeIntervalSince1970), radix: 36)
        let prefix = String(repeating: "0", count: max(0, 7 - seconds.count)) + seconds
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        // 64-character alphabet, so `& 63` keeps it uniform.
        let random = String(bytes.map { alphabet[Int($0 & 63)] })
        return prefix + random
    }
}

nonisolated enum SessionFile: String, Codable, CaseIterable, Sendable {
    case strip = "strip.jpg"
    case live = "live.mp4"

    var contentType: String {
        switch self {
        case .strip: return "image/jpeg"
        case .live: return "video/mp4"
        }
    }
}

// MARK: - Upload queue

/// Uploads each session's strip.jpg and live.mp4 to the photo page in the
/// background. The queue is saved to disk, so if Wi-Fi drops or the app
/// restarts it keeps retrying until both files are up. Uploaded sessions'
/// local copies are then deleted; nothing is kept longer than 3 days (the
/// photo page deletes everything after 3 days too, so later uploads are pointless).
@MainActor
final class UploadQueue: ObservableObject {
    static let shared = UploadQueue()

    enum FileState: String, Codable { case waiting, pending, uploaded, failed }

    struct Entry: Codable, Identifiable {
        let id: String
        let createdAt: Date
        var files: [SessionFile: FileState]
        var isComplete: Bool { SessionFile.allCases.allSatisfy { files[$0] == .uploaded } }
    }

    @Published private(set) var entries: [String: Entry] = [:]
    @Published private(set) var isOnline = true

    /// The session on screen 04 right now — its files stay on disk (the
    /// live preview is playing them) until the guest leaves.
    var activeSessionID: String? {
        didSet { if activeSessionID != oldValue { cleanUp() } }
    }

    static let maxAge: TimeInterval = 3 * 24 * 60 * 60

    private var started = false
    private var worker: Task<Void, Never>?
    private var retryDelay: TimeInterval = 5
    private let monitor = NWPathMonitor()
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 10 * 60
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private var stateURL: URL {
        LiveExporter.sessionsRoot.deletingLastPathComponent().appendingPathComponent("upload-queue.json")
    }

    private init() {}

    // MARK: Public

    /// Call once at launch: reloads the saved queue, drops anything older
    /// than 3 days, and resumes uploading.
    func start() {
        guard !started else { return }
        started = true
        load()
        purgeOld()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let online = path.status == .satisfied
                let cameBack = online && !self.isOnline
                self.isOnline = online
                if cameBack { self.retryDelay = 5; self.kick() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "upload.network"))
        kick()
    }

    /// A new session: shows as "Uploading…" right away, before any file exists.
    func register(_ sessionID: String) {
        guard entries[sessionID] == nil else { return }
        entries[sessionID] = Entry(id: sessionID, createdAt: Date(),
                                   files: Dictionary(uniqueKeysWithValues: SessionFile.allCases.map { ($0, .waiting) }))
        save()
    }

    /// A file is on disk and ready to upload.
    func fileReady(_ sessionID: String, _ file: SessionFile) {
        register(sessionID)
        entries[sessionID]?.files[file] = .pending
        save()
        kick()
    }

    func isReady(_ sessionID: String) -> Bool {
        entries[sessionID]?.isComplete ?? false
    }

    // MARK: Worker

    private func kick() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            await self?.drain()
            self?.worker = nil
        }
    }

    private func drain() async {
        guard let config = DeliveryConfig.shared else { return }
        while let (id, file) = nextPending() {
            let local = LiveExporter.sessionsRoot.appendingPathComponent(id).appendingPathComponent(file.rawValue)
            guard FileManager.default.fileExists(atPath: local.path) else {
                entries[id]?.files[file] = .failed
                save()
                continue
            }
            switch await upload(local, id: id, file: file, config: config) {
            case .success:
                entries[id]?.files[file] = .uploaded
                retryDelay = 5
                save()
                cleanUp()
            case .permanentFailure:
                entries[id]?.files[file] = .failed
                save()
            case .retryLater:
                // Back off (5 s → 60 s), or resume sooner when the network returns.
                let delay = retryDelay
                retryDelay = min(retryDelay * 2, 60)
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    private func nextPending() -> (String, SessionFile)? {
        for entry in entries.values.sorted(by: { $0.createdAt < $1.createdAt }) {
            for file in SessionFile.allCases where entry.files[file] == .pending {
                return (entry.id, file)
            }
        }
        return nil
    }

    private enum Outcome { case success, retryLater, permanentFailure }

    private func upload(_ local: URL, id: String, file: SessionFile, config: DeliveryConfig) async -> Outcome {
        var request = URLRequest(url: config.uploadURL(for: id, file: file))
        request.httpMethod = "PUT"
        request.setValue(config.boothKey, forHTTPHeaderField: "X-Booth-Key")
        request.setValue(file.contentType, forHTTPHeaderField: "Content-Type")
        do {
            let (_, response) = try await session.upload(for: request, fromFile: local)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch status {
            case 200..<300: return .success
            // Bad id / file / type / size: retrying won't help.
            case 400, 411, 413, 415: return .permanentFailure
            default: return .retryLater // 401 (key not set yet), 5xx, etc.
            }
        } catch {
            return .retryLater // offline, timeout
        }
    }

    // MARK: Cleanup

    /// Deletes local copies of fully uploaded sessions (except the one on
    /// screen) and anything older than 3 days.
    private func cleanUp() {
        for entry in entries.values where entry.isComplete && entry.id != activeSessionID {
            try? FileManager.default.removeItem(at: LiveExporter.sessionsRoot.appendingPathComponent(entry.id))
            entries[entry.id] = nil
        }
        save()
    }

    private func purgeOld() {
        let cutoff = Date().addingTimeInterval(-Self.maxAge)
        for entry in entries.values where entry.createdAt < cutoff {
            entries[entry.id] = nil
        }
        // Also any folder on disk older than 3 days (including ones from
        // before the queue existed).
        let fm = FileManager.default
        let folders = (try? fm.contentsOfDirectory(at: LiveExporter.sessionsRoot,
                                                   includingPropertiesForKeys: [.creationDateKey])) ?? []
        for folder in folders {
            let created = (try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            if created < cutoff { try? fm.removeItem(at: folder) }
        }
        save()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: stateURL),
              let list = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        entries = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        // An interrupted export never finished writing; nothing to upload.
        for (id, entry) in entries {
            for (file, state) in entry.files where state == .waiting {
                let local = LiveExporter.sessionsRoot.appendingPathComponent(id).appendingPathComponent(file.rawValue)
                if FileManager.default.fileExists(atPath: local.path) { entries[id]?.files[file] = .pending }
            }
        }
    }

    private func save() {
        try? FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(Array(entries.values)) {
            try? data.write(to: stateURL, options: .atomic)
        }
    }
}
