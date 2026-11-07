import Testing
@testable import SoeYakuApp

@MainActor struct CaptureSetupCacheTests {
    private struct Failure: Error, Equatable { let setup: Int }

    /// Counts prepared setups and records which setup each capture used; `failing` setups fail their capture.
    private final class Camera {
        var prepared = 0
        var shots: [Int] = []
        var failing: Set<Int> = []
        var keep = true

        func prepare() -> (setup: Int, keep: Bool) {
            prepared += 1
            return (prepared, keep)
        }

        func shoot(_ setup: Int) throws -> String {
            shots.append(setup)
            if failing.contains(setup) { throw Failure(setup: setup) }
            return "image \(setup)"
        }
    }

    private func capture(_ cache: CaptureSetupCache<Int, Int>, _ key: Int, with camera: Camera) async throws -> String {
        try await cache.capture(for: key, prepare: { camera.prepare() }, shoot: { try camera.shoot($0) })
    }

    @Test func reusesTheSetupForTheSameKeyAndPreparesANewOneWhenTheKeyChanges() async throws {
        let cache = CaptureSetupCache<Int, Int>(), camera = Camera()
        #expect(try await capture(cache, 1, with: camera) == "image 1")
        #expect(try await capture(cache, 1, with: camera) == "image 1")
        #expect(try await capture(cache, 2, with: camera) == "image 2")
        #expect(camera.prepared == 2)
        #expect(camera.shots == [1, 1, 2])
    }

    @Test func aFailedCaptureWithAReusedSetupIsRetriedOnceWithAFreshSetup() async throws {
        let cache = CaptureSetupCache<Int, Int>(), camera = Camera()
        _ = try await capture(cache, 1, with: camera)
        camera.failing = [1]
        #expect(try await capture(cache, 1, with: camera) == "image 2")
        #expect(camera.shots == [1, 1, 2])
        #expect(try await capture(cache, 1, with: camera) == "image 2")
        #expect(camera.prepared == 2)
    }

    @Test func aFailedCaptureWithAFreshSetupThrowsAndTheNextFramePreparesAgain() async throws {
        let cache = CaptureSetupCache<Int, Int>(), camera = Camera()
        camera.failing = [1, 2]
        await #expect(throws: Failure(setup: 1)) { try await capture(cache, 1, with: camera) }
        #expect(camera.shots == [1])
        await #expect(throws: Failure(setup: 2)) { try await capture(cache, 1, with: camera) }
        #expect(camera.shots == [1, 2])
        #expect(camera.prepared == 2)
    }

    @Test func aSetupThatMustNotBeKeptIsPreparedForEveryFrame() async throws {
        let cache = CaptureSetupCache<Int, Int>(), camera = Camera()
        camera.keep = false
        _ = try await capture(cache, 1, with: camera)
        #expect(try await capture(cache, 1, with: camera) == "image 2")
        #expect(camera.prepared == 2)
    }
}
