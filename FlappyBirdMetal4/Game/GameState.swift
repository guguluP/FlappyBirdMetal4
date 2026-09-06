import Foundation
import simd

enum GamePhase: Equatable {
    case ready
    case playing
    case gameOver
}

struct PipePair {
    /// Horizontal center in world units (0...worldWidth)
    var x: Float
    /// Vertical center of the gap in world units
    var gapY: Float
    var scored: Bool
    /// Optional collectible coin floating in the gap
    var hasCoin: Bool
    var coinCollected: Bool
}

struct Collectible {
    var x: Float
    var y: Float
    var spin: Float
    var active: Bool
}

struct FeatherParticle {
    var x: Float
    var y: Float
    var vx: Float
    var vy: Float
    var life: Float
    var maxLife: Float
    var size: Float
    var hue: Float
}

/// Fixed world space: width 9, height 16 (phone-like portrait).
/// Origin bottom-left. Rendered with 3D extrusion + lighting by Metal.
final class GameState {
    static let worldWidth: Float = 9
    static let worldHeight: Float = 16

    static let birdRadius: Float = 0.38
    static let birdX: Float = 2.4
    static let gravity: Float = -28
    static let flapVelocity: Float = 9.2
    static let pipeWidth: Float = 1.15
    static let pipeGap: Float = 3.4
    static let pipeSpeed: Float = 3.4
    static let pipeSpacing: Float = 4.2
    static let groundHeight: Float = 1.6
    static let ceilingMargin: Float = 0.2
    static let coinRadius: Float = 0.28
    static let maxParticles = 48

    private(set) var phase: GamePhase = .ready
    private(set) var score: Int = 0
    private(set) var coinsCollected: Int = 0
    private(set) var birdY: Float = worldHeight * 0.55
    private(set) var birdVelocity: Float = 0
    private(set) var birdRotation: Float = 0
    /// Wing flap cycle 0...1 for 3D character animation
    private(set) var wingPhase: Float = 0
    private(set) var pipes: [PipePair] = []
    private(set) var groundOffset: Float = 0
    private(set) var backgroundTime: Float = 0
    private(set) var particles: [FeatherParticle] = []

    private var rng = SystemRandomNumberGenerator()
    private var flapBoost: Float = 0

    func resetToReady() {
        phase = .ready
        score = 0
        coinsCollected = 0
        birdY = Self.worldHeight * 0.55
        birdVelocity = 0
        birdRotation = 0
        wingPhase = 0
        pipes = []
        particles = []
        groundOffset = 0
        flapBoost = 0
        spawnInitialPipes()
    }

    func startIfNeeded() {
        if phase == .ready {
            phase = .playing
            birdVelocity = Self.flapVelocity
            emitFlapParticles()
        } else if phase == .gameOver {
            resetToReady()
            phase = .playing
            birdVelocity = Self.flapVelocity
            emitFlapParticles()
        }
    }

    func flap() {
        switch phase {
        case .ready:
            startIfNeeded()
        case .playing:
            birdVelocity = Self.flapVelocity
            flapBoost = 1
            wingPhase = 0
            emitFlapParticles()
        case .gameOver:
            resetToReady()
            phase = .playing
            birdVelocity = Self.flapVelocity
            emitFlapParticles()
        }
    }

    func update(dt: Float) {
        let clampedDT = min(max(dt, 0), 1.0 / 20.0)
        backgroundTime += clampedDT
        groundOffset = (groundOffset + Self.pipeSpeed * clampedDT).truncatingRemainder(dividingBy: 1.2)

        // Always animate wing slightly
        wingPhase += clampedDT * (phase == .playing ? 10.0 + flapBoost * 8.0 : 3.5)
        if wingPhase > .pi * 2 { wingPhase -= .pi * 2 }
        flapBoost = max(0, flapBoost - clampedDT * 3.5)

        updateParticles(dt: clampedDT)

        guard phase == .playing else {
            if phase == .ready {
                birdY = Self.worldHeight * 0.55 + sinf(backgroundTime * 3.2) * 0.18
                birdRotation = sinf(backgroundTime * 3.2) * 0.12
            }
            return
        }

        birdVelocity += Self.gravity * clampedDT
        birdY += birdVelocity * clampedDT
        birdRotation = max(-0.9, min(1.2, birdVelocity * 0.08))

        for i in pipes.indices {
            pipes[i].x -= Self.pipeSpeed * clampedDT
            if !pipes[i].scored && pipes[i].x + Self.pipeWidth * 0.5 < Self.birdX {
                pipes[i].scored = true
                score += 1
            }
            tryCollectCoin(index: i)
        }

        while let first = pipes.first, first.x < -Self.pipeWidth {
            pipes.removeFirst()
            let lastX = pipes.last?.x ?? Self.worldWidth
            pipes.append(makePipe(x: lastX + Self.pipeSpacing))
        }

        if checkCollision() {
            phase = .gameOver
            birdVelocity = 0
            emitCrashParticles()
        }
    }

    private func tryCollectCoin(index: Int) {
        guard pipes[index].hasCoin, !pipes[index].coinCollected else { return }
        let cx = pipes[index].x
        let cy = pipes[index].gapY
        let dx = cx - Self.birdX
        let dy = cy - birdY
        let dist = sqrtf(dx * dx + dy * dy)
        if dist < Self.birdRadius + Self.coinRadius {
            pipes[index].coinCollected = true
            coinsCollected += 1
            score += 2
            emitCoinSparkles(x: cx, y: cy)
        }
    }

    private func emitFlapParticles() {
        let count = 6
        for _ in 0..<count {
            guard particles.count < Self.maxParticles else { break }
            let angle = Float.random(in: -0.8...0.8, using: &rng)
            particles.append(FeatherParticle(
                x: Self.birdX - 0.15,
                y: birdY,
                vx: -Float.random(in: 1.5...3.5, using: &rng),
                vy: Float.random(in: -1.2...2.0, using: &rng) + angle,
                life: 0.45,
                maxLife: 0.45,
                size: Float.random(in: 0.06...0.12, using: &rng),
                hue: Float.random(in: 0.08...0.18, using: &rng)
            ))
        }
    }

    private func emitCrashParticles() {
        for _ in 0..<18 {
            guard particles.count < Self.maxParticles else { break }
            let a = Float.random(in: 0...(Float.pi * 2), using: &rng)
            let sp = Float.random(in: 2...7, using: &rng)
            particles.append(FeatherParticle(
                x: Self.birdX,
                y: birdY,
                vx: cosf(a) * sp,
                vy: sinf(a) * sp,
                life: 0.7,
                maxLife: 0.7,
                size: Float.random(in: 0.05...0.14, using: &rng),
                hue: Float.random(in: 0.05...0.2, using: &rng)
            ))
        }
    }

    private func emitCoinSparkles(x: Float, y: Float) {
        for _ in 0..<10 {
            guard particles.count < Self.maxParticles else { break }
            let a = Float.random(in: 0...(Float.pi * 2), using: &rng)
            let sp = Float.random(in: 1.5...4.5, using: &rng)
            particles.append(FeatherParticle(
                x: x, y: y,
                vx: cosf(a) * sp,
                vy: sinf(a) * sp,
                life: 0.5,
                maxLife: 0.5,
                size: Float.random(in: 0.04...0.1, using: &rng),
                hue: 0.12 // gold-ish index for renderer
            ))
        }
    }

    private func updateParticles(dt: Float) {
        var i = 0
        while i < particles.count {
            particles[i].life -= dt
            if particles[i].life <= 0 {
                particles.remove(at: i)
                continue
            }
            particles[i].x += particles[i].vx * dt
            particles[i].y += particles[i].vy * dt
            particles[i].vy -= 6 * dt
            particles[i].vx *= (1 - 1.5 * dt)
            i += 1
        }
    }

    private func spawnInitialPipes() {
        pipes.removeAll(keepingCapacity: true)
        var x: Float = Self.worldWidth + 1.5
        for i in 0..<5 {
            pipes.append(makePipe(x: x, forceCoin: i % 2 == 0))
            x += Self.pipeSpacing
        }
    }

    private func makePipe(x: Float, forceCoin: Bool? = nil) -> PipePair {
        let minY = Self.groundHeight + Self.pipeGap * 0.5 + 0.6
        let maxY = Self.worldHeight - Self.ceilingMargin - Self.pipeGap * 0.5 - 0.6
        let gapY = Float.random(in: minY...maxY, using: &rng)
        let hasCoin = forceCoin ?? (Int.random(in: 0...2, using: &rng) != 0)
        return PipePair(x: x, gapY: gapY, scored: false, hasCoin: hasCoin, coinCollected: false)
    }

    private func checkCollision() -> Bool {
        let birdMinY = Self.groundHeight + Self.birdRadius
        let birdMaxY = Self.worldHeight - Self.ceilingMargin - Self.birdRadius
        if birdY < birdMinY || birdY > birdMaxY {
            return true
        }

        let bx = Self.birdX
        let by = birdY
        let r = Self.birdRadius * 0.88

        for pipe in pipes {
            let left = pipe.x - Self.pipeWidth * 0.5
            let right = pipe.x + Self.pipeWidth * 0.5
            if bx + r < left || bx - r > right { continue }

            let gapBottom = pipe.gapY - Self.pipeGap * 0.5
            let gapTop = pipe.gapY + Self.pipeGap * 0.5
            if by - r < gapBottom || by + r > gapTop {
                return true
            }
        }
        return false
    }
}
