import Darwin
import Foundation
import Testing
@testable import SoeYakuRuntime

@MainActor struct ModelServerTests {
    // A real child with the same argv and readiness contract as the bundled
    // launcher. No model, microphone, or user's llama-server process is needed.
    private final class Fixture {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var executable: URL { dir.appendingPathComponent("test-server") }
        func model(_ mode: String) -> URL { dir.appendingPathComponent(mode) }

        init() throws {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
            let script = #"""
            #!/usr/bin/python3
            import http.server, json, os, signal, sys, time
            model, port = sys.argv[1:]
            mode = os.path.basename(model)
            with open(model + ".pid", "w") as f:
                f.write(str(os.getpid()))
            if mode == "exit":
                sys.exit(7)
            if mode == "hang":
                signal.signal(signal.SIGTERM, signal.SIG_IGN)
                time.sleep(45)
            class Handler(http.server.BaseHTTPRequestHandler):
                def do_GET(self):
                    if self.path == "/health":
                        code, body = 200, {"status": "ok"}
                    elif self.headers.get("Authorization") != "Bearer " + os.environ["LLAMA_API_KEY"]:
                        code, body = 401, {}
                    else:
                        alias = "another server" if mode == "wrong" else os.environ["LLAMA_ARG_ALIAS"]
                        code, body = 200, {"data": [{"id": alias}]}
                    data = json.dumps(body).encode()
                    self.send_response(code)
                    self.send_header("Content-Length", str(len(data)))
                    self.end_headers()
                    self.wfile.write(data)
            http.server.HTTPServer(("127.0.0.1", int(port)), Handler).serve_forever()
            """#
            try script.write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        }

        func childPID(_ mode: String) async throws -> pid_t {
            let file = model(mode).appendingPathExtension("pid")
            let clock = ContinuousClock()
            let deadline = clock.now + .seconds(3)
            while clock.now < deadline {
                if let value = try? String(contentsOf: file, encoding: .utf8), let pid = Int32(value) { return pid }
                try await Task.sleep(for: .milliseconds(20))
            }
            throw ModelServerError.startupFailed("テスト子プロセスが起動しませんでした。")
        }
        deinit { try? FileManager.default.removeItem(at: dir) }
    }

    @Test func startsAuthenticatedChildAndStopsOnlyItsOwnProcess() async throws {
        let fixture = try Fixture()
        let server = ModelServer()
        let other = ModelServer()
        defer { server.stop(); other.stop() }
        let port = try await server.start(executable: fixture.executable, model: fixture.model("ready"))
        let secondPort = try await other.start(executable: fixture.executable, model: fixture.model("other"))
        #expect((1...65535).contains(port) && secondPort != port)
        #expect(server.isRunning && other.isRunning && server.apiKey != nil && server.apiKey != other.apiKey)
        let pid = try await fixture.childPID("ready")
        server.stop()
        #expect(kill(pid, 0) == -1 && errno == ESRCH)
        #expect(!server.isRunning && other.isRunning && server.apiKey == nil)
    }

    @Test func earlyExitReportsTheProcessAndReleasesTheSlot() async throws {
        let fixture = try Fixture()
        let server = ModelServer()
        defer { server.stop() }
        await #expect(throws: ModelServerError.startupFailed("終了コード 7。GGUF と llama-server を確認してください。")) {
            try await server.start(executable: fixture.executable, model: fixture.model("exit"))
        }
        #expect(!server.isRunning)
        _ = try await server.start(executable: fixture.executable, model: fixture.model("ready"))
    }

    @Test func visibleHealthFromAnotherModelCannotCompleteStartup() async throws {
        let fixture = try Fixture()
        let server = ModelServer(readyTimeout: .seconds(1))
        defer { server.stop() }
        await #expect(throws: ModelServerError.timedOut) {
            try await server.start(executable: fixture.executable, model: fixture.model("wrong"))
        }
        let pid = try await fixture.childPID("wrong")
        #expect(kill(pid, 0) == -1 && errno == ESRCH)
    }

    @Test func cancelKillsEvenAChildIgnoringTerminate() async throws {
        let fixture = try Fixture()
        let server = ModelServer()
        defer { server.stop() }
        let start = Task { try await server.start(executable: fixture.executable, model: fixture.model("hang")) }
        let pid = try await fixture.childPID("hang")
        start.cancel()
        await #expect(throws: CancellationError.self) { try await start.value }
        #expect(kill(pid, 0) == -1 && errno == ESRCH)
        #expect(!server.isRunning && server.apiKey == nil)
    }

    @Test func stoppedAttemptCannotTearDownItsReplacement() async throws {
        let fixture = try Fixture()
        let server = ModelServer()
        defer { server.stop() }
        let start = Task { try await server.start(executable: fixture.executable, model: fixture.model("hang")) }
        _ = try await fixture.childPID("hang")
        server.stop()
        _ = try await server.start(executable: fixture.executable, model: fixture.model("ready"))
        await #expect(throws: CancellationError.self) { try await start.value }
        #expect(server.isRunning)
    }
}
