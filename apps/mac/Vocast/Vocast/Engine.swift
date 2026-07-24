import Foundation

// MARK: - Engine client
//
// Talks to the local Python engine (Flask) over HTTP. The engine is the same one
// used by the web app: it does the real denoise / clone / narration work. The Mac
// app is the shell; here we wrap the endpoints we need.

struct EngineHealth: Decodable {
    let ok: Bool
    let denoise: Bool
    let clone: Bool
    let resynth: Bool
    let denoise_engine: String?
}

struct DNReport: Decodable {
    let speech_loss_pct: Double?
    let pause_supp_db: Double?
    let sim: Double?
}

struct DNJob: Decodable {
    let id: String
    let status: String          // running | done | error
    let stage: String           // extract | preview | report | done
    let title: String?
    let out_name: String?
    let mode: String?
    let engine: String?
    let duration: Double?
    let eta_sec: Double?
    let elapsed_sec: Double?
    let size_mb: Double?
    let error: String?
    let report: DNReport?
}

// MARK: Narration (Studio) decodables

struct ProfileStats: Decodable { let duration: Double? }

struct ProfileVersion: Decodable, Identifiable {
    let version: Int
    let built: String?
    var id: Int { version }
}

struct EngineProfile: Decodable, Identifiable {
    let id: String
    let name: String
    var version: Int?
    var recordings: Int?
    var ready: Bool?
    var built: String?
    var stats: ProfileStats?
    var version_log: [ProfileVersion]?
    var lang: String?          // which language this voice speaks

    /// How the voice's language reads in the UI. Profiles made before languages
    /// existed have none, and the engine treats those as Korean.
    var languageLabel: String { (lang ?? "ko") == "en" ? "English" : "한국어" }

    var clipCount: Int { recordings ?? 0 }
    var durationSec: Double { stats?.duration ?? 0 }
    var versionLabel: String { "v\(version ?? 1)" }
    var initials: String { String(name.trimmingCharacters(in: .whitespaces).prefix(2)).uppercased() }
}

struct NWord: Decodable { let w: String; let s: Double; let e: Double }
struct NPara: Decodable {
    let text: String
    let start: Double?
    let end: Double?
    let pns: Double?            // prosody north-star for this paragraph (0...100)
}

/// One scored take. The engine generates several per paragraph and keeps the best;
/// the sub-scores are all 0...1 where higher is better (they enter the selection
/// score as `-PENALTY * (1 - value)`).
struct NTake: Decodable {
    let pns: Double?
    let sel: Double?
    let ending: Double?         // ending style match
    let stress: Double?         // syllable energy stress
    let cliff: Double?          // ending pitch drop (not falling off a cliff)
    let wdrop: Double?
    let swallow: Double?        // words not swallowed
    let rate: Double?           // articulation rate, syllables per second
    let best: Bool?
    let para: Int?              // 1-based paragraph, absent on single-paragraph jobs
}

struct NJob: Decodable {
    let id: String
    let status: String          // preparing | generating | done | error
    let stage: String?
    let eta_sec: Double?
    let elapsed_sec: Double?
    let paragraphs: [NPara]?
    let words: [NWord]?
    let takes: [NTake]?
    let pns: Double?
    let rtf: Double?
    let profile: String?
    let text: String?
    let error: String?
}

/// A parent link on a regenerated narration: the paragraph regen forked from a
/// finished job, so its history entry points back at the job it descends from.
struct NParentLink: Decodable { let job: String? }

/// One saved narration from /api/history. This is the persistent library source:
/// the engine writes every finished narration to disk, so these survive an app
/// restart. `parent` is set on paragraph regenerations, which fork a new id from
/// their source job; the library collapses each parent chain into one project.
struct NHistoryItem: Decodable {
    let id: String
    let kind: String?           // nil / "clone" for narrations; others are filtered out
    let title: String?
    let status: String?         // preparing | generating | done | error
    let created: String?
    let profile: String?        // voice name at render time
    let profile_id: String?     // the voice used, or nil when made from an upload
    let version: Int?
    let parent: NParentLink?
    let paragraphs: [NPara]?
    let words: [NWord]?
    let text: String?
    let error: String?
}

/// One entry from /api/tasks: a clone, denoise or profile-build job.
struct ETask: Decodable {
    let id: String
    let kind: String?           // clone | denoise | profile_build
    let title: String?
    let status: String?         // preparing | generating | running | done | error
    let stage: String?
    let created: String?
    let eta_sec: Double?
    let elapsed_sec: Double?
    let error: String?
    let pns: Double?
    let mode: String?
}

/// One cleanup job from /api/dnjobs.
struct EDenoiseJob: Decodable {
    let id: String
    let title: String?
    let name: String?
    let status: String?
    let mode: String?
    let created: String?
    let report: DNReport?
}

/// A line of the guided recording script, with the engine's coaching for it.
struct GuideLine: Decodable {
    let text: String
    let tip: String?
    let focus: String?
}

/// A tool the local MCP server exposes.
struct MCPTool: Decodable {
    let name: String
    let desc: String
}

/// Speeds measured on this Mac. `clone_rtf` is processing seconds per second of
/// audio produced, so 20 means rendering runs 20 times slower than realtime.
struct EngineRates: Decodable {
    let clone_rtf: Double?
    let clone_fast_rtf: Double?
    let dn_standard: Double?
    let dn_resynth: Double?

    /// How the render speed reads to a person, from the measured number.
    var narrationSpeedLabel: String? {
        guard let r = clone_rtf, r > 0 else { return nil }
        return String(format: "~%.0fx slower than realtime", r)
    }
}

// MARK: Model download

struct ModelStatus: Decodable {
    let tier: String
    let downloading: Bool
    let ready: Bool
    let current: String?
    let downloaded_mb: Int
    let total_mb: Int
    let error: String?
    let installed: [String: Bool]

    var downloadedGB: Double { Double(downloaded_mb) / 1024 }
    var totalGB: Double { Double(total_mb) / 1024 }
    var fraction: Double { total_mb > 0 ? min(1, Double(downloaded_mb) / Double(total_mb)) : 0 }
}

enum EngineError: LocalizedError {
    case badResponse(Int, String)
    case notAvailable(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .badResponse(_, let msg): return msg
        case .notAvailable(let msg): return msg
        case .transport(let msg): return msg
        }
    }
}

final class EngineClient {
    var base: URL
    private let session: URLSession

    init(base: URL? = nil) {
        if let base {
            self.base = base
        } else if let s = ProcessInfo.processInfo.environment["VOCAST_ENGINE_URL"],
                  let u = URL(string: s) {
            self.base = u
        } else {
            self.base = URL(string: "http://127.0.0.1:8756")!
        }
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.waitsForConnectivity = false
        self.session = URLSession(configuration: cfg)
    }

    // MARK: Health

    func health() async throws -> EngineHealth {
        let (data, resp) = try await get("/api/health")
        try check(resp, data)
        return try JSONDecoder().decode(EngineHealth.self, from: data)
    }

    /// Poll health until reachable or `deadline` seconds pass.
    func waitUntilReady(timeout: TimeInterval = 40) async -> EngineHealth? {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if let h = try? await health(), h.ok { return h }
            try? await Task.sleep(nanoseconds: 700_000_000)
        }
        return nil
    }

    // MARK: Denoise

    /// Upload a file and start a denoise job. Returns the job id.
    func createDenoise(fileURL: URL, mode: String, boost: Double = 0) async throws -> String {
        var fields: [MultipartField] = [
            .text(name: "mode", value: mode),
            .text(name: "boost", value: String(boost)),
        ]
        let data = try Data(contentsOf: fileURL)
        fields.append(.file(name: "file", filename: fileURL.lastPathComponent,
                            mime: mimeType(for: fileURL), data: data))
        let (respData, resp) = try await multipartPost("/api/dnjobs", fields: fields)
        try check(resp, respData)
        struct R: Decodable { let job_id: String }
        return try JSONDecoder().decode(R.self, from: respData).job_id
    }

    func denoiseStatus(_ id: String) async throws -> DNJob {
        let (data, resp) = try await get("/api/dnjobs/\(id)")
        try check(resp, data)
        return try JSONDecoder().decode(DNJob.self, from: data)
    }

    /// Playable URL for the A/B preview. kind: "orig" | "clean".
    func denoiseAudioURL(_ id: String, kind: String) -> URL {
        base.appendingPathComponent("api/dnjobs/\(id)/audio/\(kind)")
    }

    /// Download URL for the cleaned result file.
    func denoiseFileURL(_ id: String) -> URL {
        base.appendingPathComponent("api/dnjobs/\(id)/file")
    }

    // MARK: Models

    func modelStatus() async throws -> ModelStatus {
        let (data, resp) = try await get("/api/models/status")
        try check(resp, data)
        return try JSONDecoder().decode(ModelStatus.self, from: data)
    }

    func startModelDownload(tier: String) async throws {
        var req = URLRequest(url: base.appendingPathComponent("api/models/download"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["tier": tier])
        do {
            let (data, resp) = try await session.data(for: req)
            try check(resp, data)
        } catch let e as EngineError {
            throw e
        } catch {
            throw EngineError.transport(error.localizedDescription)
        }
    }

    // MARK: Narration (Studio)

    func listProfiles() async throws -> [EngineProfile] {
        let (data, resp) = try await get("/api/profiles")
        try check(resp, data)
        struct R: Decodable { let profiles: [EngineProfile] }
        return try JSONDecoder().decode(R.self, from: data).profiles
    }

    func createProfile(name: String, lang: String) async throws -> String {
        let (data, resp) = try await multipartPost("/api/profiles", fields: [
            .text(name: "name", value: name),
            .text(name: "lang", value: lang),
        ])
        try check(resp, data)
        struct R: Decodable { let id: String }
        return try JSONDecoder().decode(R.self, from: data).id
    }

    func addRecording(pid: String, fileURL: URL, idx: Int) async throws {
        let bytes = try Data(contentsOf: fileURL)
        let (data, resp) = try await multipartPost("/api/profiles/\(pid)/recordings", fields: [
            .file(name: "audio", filename: fileURL.lastPathComponent, mime: "audio/wav", data: bytes),
            .text(name: "idx", value: String(idx)),
        ])
        try check(resp, data)
    }

    func addSource(pid: String, fileURL: URL) async throws {
        let bytes = try Data(contentsOf: fileURL)
        let (data, resp) = try await multipartPost("/api/profiles/\(pid)/sources", fields: [
            .file(name: "audio", filename: fileURL.lastPathComponent, mime: mimeType(for: fileURL), data: bytes),
        ])
        try check(resp, data)
    }

    func buildProfile(pid: String) async throws -> String {
        let (data, resp) = try await jsonPost("/api/profiles/\(pid)/build_async", body: [:])
        try check(resp, data)
        struct R: Decodable { let job_id: String }
        return try JSONDecoder().decode(R.self, from: data).job_id
    }

    func rollbackProfile(pid: String, version: Int) async throws {
        let (data, resp) = try await jsonPost("/api/profiles/\(pid)/rollback", body: ["version": version])
        try check(resp, data)
    }

    func deleteProfile(pid: String) async throws {
        var req = URLRequest(url: base.appendingPathComponent("api/profiles/\(pid)"))
        req.httpMethod = "DELETE"
        do {
            let (data, resp) = try await session.data(for: req)
            try check(resp, data)
        } catch let e as EngineError { throw e }
        catch { throw EngineError.transport(error.localizedDescription) }
    }

    private func jsonPost(_ path: String, body: [String: Any]) async throws -> (Data, URLResponse) {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        do { return try await session.data(for: req) }
        catch { throw EngineError.transport(error.localizedDescription) }
    }

    private func patch(_ path: String, body: [String: Any]) async throws -> (Data, URLResponse) {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        do { return try await session.data(for: req) }
        catch { throw EngineError.transport(error.localizedDescription) }
    }

    func createNarration(text: String, profileID: String?, fast: Bool = false) async throws -> String {
        var fields: [MultipartField] = [
            .text(name: "text", value: text),
            .text(name: "fast", value: fast ? "1" : "0"),
        ]
        if let p = profileID { fields.append(.text(name: "profile_id", value: p)) }
        let (data, resp) = try await multipartPost("/api/jobs", fields: fields)
        try check(resp, data)
        struct R: Decodable { let job_id: String }
        return try JSONDecoder().decode(R.self, from: data).job_id
    }

    func narrationStatus(_ id: String) async throws -> NJob {
        let (data, resp) = try await get("/api/jobs/\(id)")
        try check(resp, data)
        return try JSONDecoder().decode(NJob.self, from: data)
    }

    /// Re-render a single paragraph of a finished narration job without redoing the
    /// whole thing (Studio-style partial regeneration). Returns a new job id that
    /// composes the updated paragraph back into the full audio.
    func regenerateParagraph(jobID: String, paragraph: Int) async throws -> String {
        let (data, resp) = try await jsonPost("/api/jobs/\(jobID)/regen",
                                              body: ["paragraph": paragraph])
        try check(resp, data)
        struct R: Decodable { let job_id: String }
        return try JSONDecoder().decode(R.self, from: data).job_id
    }

    /// Playable URL for the composed narration audio.
    func narrationAudioURL(_ id: String) -> URL {
        base.appendingPathComponent("api/jobs/\(id)/audio")
    }

    // MARK: Narration library (persisted history)

    /// Every saved narration the engine has on disk, newest first. This is the
    /// Studio library's source of truth: it survives app restarts because the
    /// engine persists each finished narration under its history store.
    func listHistory() async throws -> [NHistoryItem] {
        let (data, resp) = try await get("/api/history")
        try check(resp, data)
        struct R: Decodable { let items: [NHistoryItem] }
        return try JSONDecoder().decode(R.self, from: data).items
    }

    /// Rename a saved narration. The new title is what the library row shows.
    func renameHistory(id: String, title: String) async throws {
        let (data, resp) = try await patch("/api/history/\(id)", body: ["title": title])
        try check(resp, data)
    }

    /// Delete a saved narration from the library (removes its doc and audio).
    func deleteHistory(id: String) async throws {
        var req = URLRequest(url: base.appendingPathComponent("api/history/\(id)"))
        req.httpMethod = "DELETE"
        do {
            let (data, resp) = try await session.data(for: req)
            try check(resp, data)
        } catch let e as EngineError { throw e }
        catch { throw EngineError.transport(error.localizedDescription) }
    }

    /// The raw persisted job document, verbatim. Used when bundling a `.vocast`
    /// project file so the export keeps every field the engine stored, not just
    /// the ones the app decodes.
    func rawJob(_ id: String) async throws -> Data {
        let (data, resp) = try await get("/api/jobs/\(id)")
        try check(resp, data)
        return data
    }

    /// Download URL for an exported narration. `format` is wav or mp3; `blocks` (0-based
    /// paragraph indices) narrows the export to selected blocks, whole when nil.
    func exportAudioURL(_ id: String, format: String, blocks: [Int]?) -> URL {
        var comps = URLComponents(url: base.appendingPathComponent("api/jobs/\(id)/export"),
                                  resolvingAgainstBaseURL: false)!
        var q = [URLQueryItem(name: "format", value: format)]
        if let blocks, !blocks.isEmpty {
            q.append(URLQueryItem(name: "blocks", value: blocks.map(String.init).joined(separator: ",")))
        }
        comps.queryItems = q
        return comps.url!
    }

    /// Duplicate a saved narration into a new history entry. Returns the new id.
    func duplicateHistory(id: String, title: String?) async throws -> String {
        let (data, resp) = try await jsonPost("/api/history/\(id)/duplicate",
                                              body: title.map { ["title": $0] } ?? [:])
        try check(resp, data)
        struct R: Decodable { let id: String }
        return try JSONDecoder().decode(R.self, from: data).id
    }

    /// Register a `.vocast` bundle (its manifest JSON + audio) as a new saved
    /// narration. Returns the new id.
    func importHistory(manifest: Data, audio: Data) async throws -> String {
        let manifestStr = String(data: manifest, encoding: .utf8) ?? "{}"
        let (data, resp) = try await multipartPost("/api/history/import", fields: [
            .text(name: "manifest", value: manifestStr),
            .file(name: "audio", filename: "output.wav", mime: "audio/wav", data: audio),
        ])
        try check(resp, data)
        struct R: Decodable { let id: String }
        return try JSONDecoder().decode(R.self, from: data).id
    }

    // MARK: Work already done on this Mac

    /// Every async job the engine knows about, newest and still-running first.
    /// This is the one source for the Tasks area and the toolbar indicator.
    func listTasks() async throws -> [ETask] {
        let (data, resp) = try await get("/api/tasks")
        try check(resp, data)
        struct R: Decodable { let items: [ETask] }
        return try JSONDecoder().decode(R.self, from: data).items
    }

    /// Cleanup jobs, for the Denoise area's recent list.
    func listDenoiseJobs() async throws -> [EDenoiseJob] {
        let (data, resp) = try await get("/api/dnjobs")
        try check(resp, data)
        struct R: Decodable { let items: [EDenoiseJob] }
        return try JSONDecoder().decode(R.self, from: data).items
    }

    /// The guided recording script, with the engine's per-line coaching.
    func guideLines(lang: String) async throws -> [GuideLine] {
        let (data, resp) = try await get("/api/guide?lang=\(lang)")
        try check(resp, data)
        struct R: Decodable { let sentences: [GuideLine] }
        return try JSONDecoder().decode(R.self, from: data).sentences
    }

    /// Speeds measured on this Mac, so the UI never guesses at performance.
    func rates() async throws -> EngineRates {
        let (data, resp) = try await get("/api/rates")
        try check(resp, data)
        return try JSONDecoder().decode(EngineRates.self, from: data)
    }

    /// The profile's merged reference audio, for drawing its real waveform.
    func profileAudioURL(_ pid: String) -> URL {
        base.appendingPathComponent("api/profiles/\(pid)/audio")
    }

    /// Tools the local MCP server actually exposes to an agent.
    func mcpTools() async throws -> [MCPTool] {
        let (data, resp) = try await get("/api/mcp/tools")
        try check(resp, data)
        struct R: Decodable { let items: [MCPTool] }
        return try JSONDecoder().decode(R.self, from: data).items
    }

    // MARK: HTTP plumbing

    private func get(_ path: String) async throws -> (Data, URLResponse) {
        // Resolve against the base rather than appending a path component, which
        // would percent-encode a query string's "?" and silently break the request.
        let url = URL(string: path, relativeTo: base) ?? base.appendingPathComponent(path)
        do {
            return try await session.data(from: url)
        } catch {
            throw EngineError.transport(error.localizedDescription)
        }
    }

    private func check(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
                ?? "Engine returned \(http.statusCode)."
            if http.statusCode == 501 { throw EngineError.notAvailable(msg) }
            throw EngineError.badResponse(http.statusCode, msg)
        }
    }

    private enum MultipartField {
        case text(name: String, value: String)
        case file(name: String, filename: String, mime: String, data: Data)
    }

    private func multipartPost(_ path: String, fields: [MultipartField]) async throws -> (Data, URLResponse) {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        func append(_ s: String) { body.append(s.data(using: .utf8)!) }
        for f in fields {
            append("--\(boundary)\r\n")
            switch f {
            case .text(let name, let value):
                append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
                append("\(value)\r\n")
            case .file(let name, let filename, let mime, let data):
                append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
                append("Content-Type: \(mime)\r\n\r\n")
                body.append(data)
                append("\r\n")
            }
        }
        append("--\(boundary)--\r\n")

        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        do {
            return try await session.data(for: req)
        } catch {
            throw EngineError.transport(error.localizedDescription)
        }
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "wav": return "audio/wav"
        case "mp3": return "audio/mpeg"
        case "m4a", "aac": return "audio/mp4"
        case "mov": return "video/quicktime"
        case "mp4", "m4v": return "video/mp4"
        default: return "application/octet-stream"
        }
    }
}
