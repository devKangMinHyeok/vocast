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
    let base: URL
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

    // MARK: HTTP plumbing

    private func get(_ path: String) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(from: base.appendingPathComponent(path))
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
