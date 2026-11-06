import Foundation
import Darwin
import CFNetwork

public enum ModelServerError: LocalizedError, Equatable {
    case alreadyRunning, invalidFile, timedOut, startupFailed(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyRunning: return "翻訳サーバーはすでに起動中です。"
        case .invalidFile: return "実行ファイルとモデルにはローカルファイルを指定してください。"
        case .timedOut: return "翻訳サーバーの準備が時間内に終わりませんでした。"
        case .startupFailed(let reason): return "翻訳サーバーを起動できませんでした。\(reason)"
        }
    }
}

@MainActor public final class ModelServer {
    private let readyTimeout: Duration
    private var child: ServerChild?
    public var isRunning: Bool { child.map { $0.exitStatus == nil } ?? false }
    public var apiKey: String? { isRunning ? child?.apiKey : nil }

    public init() { readyTimeout = .seconds(90) }
    init(readyTimeout: Duration) { self.readyTimeout = readyTimeout }

    public func start(executable: URL, model: URL) async throws -> Int {
        try Task.checkCancellation()
        guard !isRunning else { throw ModelServerError.alreadyRunning }
        guard executable.isFileURL, model.isFileURL else { throw ModelServerError.invalidFile }
        let port = try availablePort()
        let attempt = try ServerChild(executable: executable, model: model, port: port)
        child = attempt
        let probe = Probe()
        defer { probe.session.invalidateAndCancel() }
        let deadline = ContinuousClock.now + readyTimeout
        do {
            repeat {
                try check(attempt)
                if await probe.ready(port: port, key: attempt.apiKey, alias: attempt.alias) {
                    try check(attempt)
                    guard ContinuousClock.now < deadline else { throw ModelServerError.timedOut }
                    return port
                }
                try await Task.sleep(for: .milliseconds(100))
            } while ContinuousClock.now < deadline
            try check(attempt)
            throw ModelServerError.timedOut
        } catch {
            if child === attempt { stop() }
            throw error
        }
    }

    private func check(_ attempt: ServerChild) throws {
        try Task.checkCancellation()
        guard child === attempt else { throw CancellationError() }
        if let status = attempt.exitStatus {
            let reason = status & 0x7f == 0 ? "終了コード \(status >> 8)" : "シグナル \(status & 0x7f)"
            throw ModelServerError.startupFailed("\(reason)。GGUF と llama-server を確認してください。")
        }
    }

    public func stop() {
        child?.stop()
        child = nil
    }
}

/// This instance is the only owner that waits on its child. Until waitpid
/// reaps it, even an exited child retains its PID: stop cannot signal a reused PID.
private final class ServerChild {
    let apiKey = UUID().uuidString + UUID().uuidString
    let alias = UUID().uuidString
    private var pid: pid_t = 0
    private var status: Int32?

    init(executable: URL, model: URL, port: Int) throws {
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        try checkPOSIX(posix_spawn_file_actions_init(&actions))
        defer { posix_spawn_file_actions_destroy(&actions) }
        try checkPOSIX(posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }
        try checkPOSIX(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT)))
        for fd in [STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO] {
            try checkPOSIX(posix_spawn_file_actions_addopen(&actions, fd, "/dev/null", fd == STDIN_FILENO ? O_RDONLY : O_WRONLY, 0))
        }
        // Whitelist the environment: debug/log/prompt file settings and
        // network credentials from an interactive shell need never reach inference.
        var env = ProcessInfo.processInfo.environment.filter { ["HOME", "TMPDIR", "LANG"].contains($0.key) }
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["LLAMA_API_KEY"] = apiKey
        env["LLAMA_ARG_ALIAS"] = alias
        let argv = [executable.path, model.path, String(port)].map { strdup($0) } + [nil]
        let envp = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
        var newPID: pid_t = 0
        try checkPOSIX(posix_spawn(&newPID, executable.path, &actions, &attributes, argv, envp))
        pid = newPID
    }

    var exitStatus: Int32? {
        guard status == nil, pid > 0 else { return status }
        var result: Int32 = 0
        let observed = waitpid(pid, &result, WNOHANG)
        if observed == pid { status = result }
        if observed == -1 && errno == ECHILD { status = -1 }
        return status
    }

    func stop() {
        guard pid > 0, exitStatus == nil else { return }
        // The server has no persistent state. Make quit synchronous even when
        // a loading engine blocks SIGTERM, then reap only the child we launched.
        kill(pid, SIGKILL)
        var result: Int32 = 0
        while waitpid(pid, &result, 0) == -1 && errno == EINTR {}
        status = result
    }

    deinit { stop() }
}

private func checkPOSIX(_ code: Int32) throws {
    if code != 0 { throw ModelServerError.startupFailed(String(cString: strerror(code))) }
}

private func availablePort() throws -> Int {
    let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
    guard socket >= 0 else { throw ModelServerError.startupFailed(String(cString: strerror(errno))) }
    defer { close(socket) }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    var size = socklen_t(MemoryLayout<sockaddr_in>.size)
    try withUnsafeMutablePointer(to: &address) { pointer in
        try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddr in
            if bind(socket, sockaddr, size) != 0 || getsockname(socket, sockaddr, &size) != 0 {
                throw ModelServerError.startupFailed(String(cString: strerror(errno)))
            }
        }
    }
    return Int(UInt16(bigEndian: address.sin_port))
}

@MainActor private final class Probe: NSObject, URLSessionTaskDelegate {
    lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1
        config.timeoutIntervalForResource = 1
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.connectionProxyDictionary = [kCFNetworkProxiesExceptionsList as String: ["127.0.0.1"],
            kCFNetworkProxiesHTTPEnable as String: false, kCFNetworkProxiesProxyAutoConfigEnable as String: false,
            kCFNetworkProxiesSOCKSEnable as String: false, kCFNetworkProxiesProxyAutoDiscoveryEnable as String: false]
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    func ready(port: Int, key: String, alias: String) async -> Bool {
        // llama-server binds after we release the port. Verify this child's
        // random alias before the app sends any document text to that port.
        guard let root = URL(string: "http://127.0.0.1:\(port)") else { return false }
        do {
            let (health, response) = try await session.data(from: root.appendingPathComponent("health"))
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  try JSONDecoder().decode(Health.self, from: health).status == "ok" else { return false }
            var request = URLRequest(url: root.appendingPathComponent("v1/models"))
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            let (data, models) = try await session.data(for: request)
            guard (models as? HTTPURLResponse)?.statusCode == 200 else { return false }
            return try JSONDecoder().decode(Models.self, from: data).data.contains { $0.id == alias }
        } catch { return false }
    }
    private struct Health: Decodable { let status: String }
    private struct Models: Decodable {
        struct Model: Decodable { let id: String }
        let data: [Model]
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
