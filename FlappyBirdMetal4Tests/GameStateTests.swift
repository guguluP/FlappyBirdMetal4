import XCTest
@testable import FlappyBirdMetal4

final class GameStateTests: XCTestCase {
    func testReadyStateAfterReset() {
        let game = GameState()
        game.resetToReady()
        XCTAssertEqual(game.phase, .ready)
        XCTAssertEqual(game.score, 0)
        XCTAssertEqual(game.coinsCollected, 0)
    }

    func testFlapFromReadyStartsPlaying() {
        let game = GameState()
        game.resetToReady()
        game.flap()
        XCTAssertEqual(game.phase, .playing)
        XCTAssertEqual(game.score, 0)
    }

    func testFallingWithoutAnotherFlapEndsTheRun() {
        let game = GameState()
        game.resetToReady()
        game.flap()
        for _ in 0..<90 where game.phase != .gameOver {
            game.update(dt: 1.0 / 30.0)
        }
        XCTAssertEqual(game.phase, .gameOver)
        XCTAssertEqual(game.score, 0)
    }

    func testFlapAfterGameOverStartsAFreshRun() {
        let game = GameState()
        game.resetToReady()
        game.flap()
        for _ in 0..<90 where game.phase != .gameOver {
            game.update(dt: 1.0 / 30.0)
        }
        XCTAssertEqual(game.phase, .gameOver)
        game.flap()
        XCTAssertEqual(game.phase, .playing)
        XCTAssertEqual(game.score, 0)
        XCTAssertEqual(game.coinsCollected, 0)
    }
}
