import Foundation
import Darwin

/// Launches and manages the local Python engine as a child process (sidecar), so the
/// app can talk to it over HTTP without the user starting a server. Picks a free port,
/// spawns the Flask server, and terminates it when the app quits.
final class Sidecar {
    private var process: Process?
    private(set) var port: Int = 0

    /// Start the engine and return its base URL (server may still be booting).
    /// Returns nil if it could not be launched (missing uv / engine dir); in that
    /// case the app falls back to whatever the EngineClient default points at.
    @discardableResult
    func start() -> URL? {
        // An external engine URL wins: do not spawn, just point at it.
        if let s = ProcessInfo.processInfo.environment["VOCAST_ENGINE_URL"],
           let u = URL(string: s) {
            return u
        }
        guard process == nil else {
            return URL(string: "http://127.0.0.1:\(port)")
        }
        guard let dir = engineDir(), let launch = launcher(in: dir) else {
            NSLog("Vocast: could not locate the engine directory or a Python launcher; not spawning sidecar.")
            return nil
        }

        let p = freePort()
        port = p

        let proc = Process()
        proc.executableURL = launch.exec
        proc.arguments = launch.args + ["--port", "\(p)"]
        proc.currentDirectoryURL = dir

        var env = ProcessInfo.processInfo.environment
        let extra = "\(launch.exec.deletingLastPathComponent().path):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["PATH"] = (env["PATH"].map { "\($0):\(extra)" }) ?? extra
        // Parent-death watchdog: the server self-exits if this app process dies,
        // so a crash cannot leave an orphaned engine behind.
        env["VOCAST_PARENT_PID"] = "\(ProcessInfo.processInfo.processIdentifier)"
        // Keep all downloaded models inside the app's own folder (not the shared
        // Hugging Face cache), so they are contained and removable with the app.
        env["HF_HOME"] = Sidecar.modelsDir().path
        // Same for torch.hub, which fetches the UTMOS model behind the prosody score.
        // Without this it lands in ~/.cache/torch and outlives the app.
        env["TORCH_HOME"] = Sidecar.modelsDir().appendingPathComponent("torch").path
        // Run the engine offline by default. Models are downloaded once (via the
        // /api/models/download path, which lifts this) and then everything runs
        // on-device. Without this, Hugging Face phones home to check the revision
        // even for a fully-cached model, and if the machine is offline that call
        // hangs forever — which is what stalled renders at the "reference"
        // (Whisper) stage. Cache hits are instant with this set.
        env["HF_HUB_OFFLINE"] = "1"
        env["TRANSFORMERS_OFFLINE"] = "1"
        proc.environment = env

        // Pipe logs to a temp file for debugging.
        let logURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("vocast-sidecar.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        if let fh = try? FileHandle(forWritingTo: logURL) {
            proc.standardOutput = fh
            proc.standardError = fh
        }

        do {
            try proc.run()
            process = proc
            NSLog("Vocast: sidecar launched on port \(p) (log: \(logURL.path))")
            return URL(string: "http://127.0.0.1:\(p)")
        } catch {
            NSLog("Vocast: failed to launch sidecar: \(error.localizedDescription)")
            return nil
        }
    }

    func stop() {
        process?.terminate()
        process = nil
    }

    /// App-owned folder for downloaded models, keyed by bundle identifier so a beta
    /// build and a release build never share one. All engine model downloads are
    /// confined here via HF_HOME and TORCH_HOME, which keeps them removable with
    /// the app that fetched them.
    static func modelsDir() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let id = Bundle.main.bundleIdentifier ?? "me.vocast.Vocast"
        let dir = base.appendingPathComponent("\(id)/models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: Location

    private func engineDir() -> URL? {
        let fm = FileManager.default
        func hasServer(_ base: String) -> Bool { fm.fileExists(atPath: base + "/api/server.py") }

        if let s = ProcessInfo.processInfo.environment["VOCAST_ENGINE_DIR"], hasServer(s) {
            return URL(fileURLWithPath: s)
        }
        // Bundled engine (Phase 4): Vocast.app/Contents/Resources/engine
        if let res = Bundle.main.resourceURL?.appendingPathComponent("engine"),
           hasServer(res.path) {
            return res
        }
        // Dev default: the repo's app/ directory.
        let dev = "\(NSHomeDirectory())/Desktop/service-development/denoise-app/app"
        if hasServer(dev) { return URL(fileURLWithPath: dev) }
        return nil
    }

    /// Prefer running the engine's venv Python directly (a single child process that
    /// terminate() cleans up directly). Fall back to `uv run` if there is no venv.
    private func launcher(in dir: URL) -> (exec: URL, args: [String])? {
        let fm = FileManager.default
        // Bundled engine uses runtime/.venv; the dev repo uses .venv.
        for rel in ["runtime/.venv/bin/python", ".venv/bin/python"] {
            let py = dir.appendingPathComponent(rel)
            if fm.isExecutableFile(atPath: py.path) { return (py, ["api/server.py"]) }
        }
        let uvCandidates = [
            "\(NSHomeDirectory())/.local/bin/uv",
            "/opt/homebrew/bin/uv",
            "/usr/local/bin/uv",
        ]
        for c in uvCandidates where fm.isExecutableFile(atPath: c) {
            return (URL(fileURLWithPath: c), ["run", "python", "api/server.py"])
        }
        return nil
    }

    // MARK: Free port

    private func freePort() -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return 8756 }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = in_addr_t(0)   // INADDR_ANY
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { return 8756 }
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &len)
            }
        }
        return Int(UInt16(bigEndian: addr.sin_port))
    }
}
