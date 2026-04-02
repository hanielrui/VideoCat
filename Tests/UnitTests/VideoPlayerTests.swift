import XCTest
@testable import VideoPlayer

final class VideoPlayerTests: XCTestCase {

    override func setUpWithError() throws {
        // 测试前设置
    }

    override func tearDownWithError() throws {
        // 测试后清理
    }

    // MARK: - URL 验证测试

    func testURLValidator_ValidHTTPS() throws {
        let validator = DefaultURLValidator()
        XCTAssertTrue(validator.validate("https://example.com/video.m3u8"))
    }

    func testURLValidator_ValidHTTP() throws {
        let validator = DefaultURLValidator()
        XCTAssertTrue(validator.validate("http://example.com/video.mp4"))
    }

    func testURLValidator_InvalidURL() throws {
        let validator = DefaultURLValidator()
        XCTAssertFalse(validator.validate("not a valid url"))
    }

    func testURLValidator_EmptyURL() throws {
        let validator = DefaultURLValidator()
        XCTAssertFalse(validator.validate(""))
    }

    // MARK: - PlayerError 测试

    func testPlayerError_InvalidURL() throws {
        let error = PlayerError.invalidURL
        XCTAssertNotNil(error.errorDescription)
    }

    func testPlayerError_LoadFailed() throws {
        let underlyingError = NSError(domain: "test", code: -1, userInfo: nil)
        let error = PlayerError.loadFailed(underlyingError)
        XCTAssertNotNil(error.errorDescription)
    }

    // MARK: - PlayerCore 测试

    func testPlayerCore_Init() throws {
        let player = PlayerCore()
        XCTAssertNotNil(player.player)
        XCTAssertFalse(player.isPlaying)
    }

    func testPlayerCore_PlayState() throws {
        let player = PlayerCore()
        XCTAssertNil(player.duration)
    }

    // MARK: - VideoCache 测试

    func testVideoCache_Singleton() throws {
        let cache1 = VideoCache.shared
        let cache2 = VideoCache.shared
        XCTAssertTrue(cache1 === cache2)
    }

    func testVideoCache_ClearCache() throws {
        let cache = VideoCache.shared
        cache.clearCache()
        let size = cache.getCurrentCacheSize()
        XCTAssertEqual(size, 0)
    }

    // MARK: - PlayerPool 测试

    func testPlayerPool_AcquireRelease() async throws {
        let pool = PlayerPool.shared
        let player1 = await pool.acquirePlayer()
        XCTAssertNotNil(player1)

        await pool.releasePlayer(player1)
    }

    func testPlayerPool_Status() async throws {
        let pool = PlayerPool.shared
        let status = await pool.status
        XCTAssertGreaterThanOrEqual(status.available, 0)
        XCTAssertGreaterThanOrEqual(status.inUse, 0)
    }

    // MARK: - 性能测试

    func testPlayerPool_Performance() async throws {
        let pool = PlayerPool.shared

        measure {
            Task {
                let player = await pool.acquirePlayer()
                await pool.releasePlayer(player)
            }
        }
    }

    // MARK: - 错误处理测试

    func testPlayerCore_InvalidURL() throws {
        let player = PlayerCore()
        let invalidURL = URL(string: "invalid://test")!

        var errorReceived = false
        player.onError = { error in
            errorReceived = true
        }

        player.play(url: invalidURL)

        // 等待异步操作
        let expectation = expectation(description: "Error callback")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 2)
    }
}
