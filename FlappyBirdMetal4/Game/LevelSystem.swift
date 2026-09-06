import Foundation
import simd

/// Convenience constructor for a colour.
@inline(__always)
func rgb(_ r: Float, _ g: Float, _ b: Float) -> SIMD3<Float> {
    SIMD3<Float>(r, g, b)
}

@inline(__always)
func mixColor(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
    a + (b - a) * t
}

@inline(__always)
func mixFloat(_ a: Float, _ b: Float, _ t: Float) -> Float {
    a + (b - a) * t
}

// MARK: - Set dressing

enum DecorKind: Int, Equatable {
    case tree
    case cactus
    case palm
    case pine
    case crystal
    case building
}

enum AmbientKind: Int, Equatable {
    case leaves
    case sand
    case petals
    case snow
    case fireflies
    case sparks
}

// MARK: - Theme

/// Complete art direction for one level. Every colour the renderer uses is read
/// from here, so switching levels re-skins the whole world — sky, terrain,
/// obstacles, lighting, the bird and the ambient particles.
struct LevelTheme {
    // Sky
    var skyTop = rgb(0.16, 0.42, 0.86)
    var skyMid = rgb(0.44, 0.72, 0.97)
    var skyHorizon = rgb(0.80, 0.91, 0.96)
    var sunColor = rgb(1.00, 0.96, 0.82)
    var sunPosition = SIMD2<Float>(0.76, 0.84)
    var sunSize: Float = 0.030
    var cloudColor = rgb(1.00, 1.00, 1.00)
    var cloudDensity: Float = 0.80
    var starDensity: Float = 0.0
    var nightAmount: Float = 0.0

    // Terrain
    var hillFar = rgb(0.20, 0.44, 0.30)
    var hillMid = rgb(0.26, 0.55, 0.32)
    var hillNear = rgb(0.34, 0.66, 0.34)
    var hillCap = rgb(0.44, 0.76, 0.42)
    /// Height above the ground where the cap colour takes over (large = no cap).
    var hillCapLine: Float = 99
    var groundTop = rgb(0.36, 0.78, 0.30)
    var groundBody = rgb(0.60, 0.42, 0.24)
    var groundStripe = rgb(0.26, 0.64, 0.22)
    var groundGlow: Float = 0.0

    // Obstacles
    var pipeBody = rgb(0.16, 0.74, 0.30)
    var pipeLip = rgb(0.32, 0.92, 0.44)
    var pipeGlow: Float = 0.0

    // Atmosphere & lighting
    var fogColor = rgb(0.72, 0.86, 0.95)
    var fogDensity: Float = 0.020
    var accent = rgb(1.00, 0.85, 0.25)
    var ambient: Float = 0.44
    var lightColor = rgb(1.05, 1.00, 0.92)
    var lightDir = SIMD3<Float>(-0.40, -0.85, -0.35)
    var exposure: Float = 1.0
    var vignette: Float = 0.30

    // Character
    var birdBody = rgb(1.00, 0.84, 0.14)
    var birdBelly = rgb(1.00, 0.96, 0.70)
    var birdWing = rgb(1.00, 0.66, 0.16)
    var birdBeak = rgb(1.00, 0.48, 0.10)

    // Decor
    var decor: DecorKind = .tree
    var decorColor = rgb(0.24, 0.50, 0.24)
    var decorTrunk = rgb(0.42, 0.28, 0.16)
    var decorGlow: Float = 0.0
    var ambientKind: AmbientKind = .leaves
    var ambientColor = rgb(0.86, 0.92, 0.48)

    /// Gradient used by the SwiftUI menus for this level.
    var uiTop = rgb(0.26, 0.60, 0.98)
    var uiBottom = rgb(0.08, 0.26, 0.58)

    static func lerp(_ a: LevelTheme, _ b: LevelTheme, _ t: Float) -> LevelTheme {
        let k = max(0, min(1, t))
        var o = LevelTheme()

        o.skyTop = mixColor(a.skyTop, b.skyTop, k)
        o.skyMid = mixColor(a.skyMid, b.skyMid, k)
        o.skyHorizon = mixColor(a.skyHorizon, b.skyHorizon, k)
        o.sunColor = mixColor(a.sunColor, b.sunColor, k)
        o.sunPosition = a.sunPosition + (b.sunPosition - a.sunPosition) * k
        o.sunSize = mixFloat(a.sunSize, b.sunSize, k)
        o.cloudColor = mixColor(a.cloudColor, b.cloudColor, k)
        o.cloudDensity = mixFloat(a.cloudDensity, b.cloudDensity, k)
        o.starDensity = mixFloat(a.starDensity, b.starDensity, k)
        o.nightAmount = mixFloat(a.nightAmount, b.nightAmount, k)

        o.hillFar = mixColor(a.hillFar, b.hillFar, k)
        o.hillMid = mixColor(a.hillMid, b.hillMid, k)
        o.hillNear = mixColor(a.hillNear, b.hillNear, k)
        o.hillCap = mixColor(a.hillCap, b.hillCap, k)
        o.hillCapLine = mixFloat(a.hillCapLine, b.hillCapLine, k)
        o.groundTop = mixColor(a.groundTop, b.groundTop, k)
        o.groundBody = mixColor(a.groundBody, b.groundBody, k)
        o.groundStripe = mixColor(a.groundStripe, b.groundStripe, k)
        o.groundGlow = mixFloat(a.groundGlow, b.groundGlow, k)

        o.pipeBody = mixColor(a.pipeBody, b.pipeBody, k)
        o.pipeLip = mixColor(a.pipeLip, b.pipeLip, k)
        o.pipeGlow = mixFloat(a.pipeGlow, b.pipeGlow, k)

        o.fogColor = mixColor(a.fogColor, b.fogColor, k)
        o.fogDensity = mixFloat(a.fogDensity, b.fogDensity, k)
        o.accent = mixColor(a.accent, b.accent, k)
        o.ambient = mixFloat(a.ambient, b.ambient, k)
        o.lightColor = mixColor(a.lightColor, b.lightColor, k)
        o.lightDir = a.lightDir + (b.lightDir - a.lightDir) * k
        o.exposure = mixFloat(a.exposure, b.exposure, k)
        o.vignette = mixFloat(a.vignette, b.vignette, k)

        o.birdBody = mixColor(a.birdBody, b.birdBody, k)
        o.birdBelly = mixColor(a.birdBelly, b.birdBelly, k)
        o.birdWing = mixColor(a.birdWing, b.birdWing, k)
        o.birdBeak = mixColor(a.birdBeak, b.birdBeak, k)

        // Discrete traits snap at the halfway point.
        o.decor = k < 0.5 ? a.decor : b.decor
        o.ambientKind = k < 0.5 ? a.ambientKind : b.ambientKind
        o.decorColor = mixColor(a.decorColor, b.decorColor, k)
        o.decorTrunk = mixColor(a.decorTrunk, b.decorTrunk, k)
        o.decorGlow = mixFloat(a.decorGlow, b.decorGlow, k)
        o.ambientColor = mixColor(a.ambientColor, b.ambientColor, k)

        o.uiTop = mixColor(a.uiTop, b.uiTop, k)
        o.uiBottom = mixColor(a.uiBottom, b.uiBottom, k)
        return o
    }
}

// MARK: - Difficulty

/// Per-level gameplay tuning. The campaign ramps these gently so level 1 is
/// friendlier than the classic game and level 6 is genuinely demanding.
struct LevelTuning {
    var pipeSpeed: Float = 3.0
    var pipeGap: Float = 3.75
    var pipeSpacing: Float = 4.6
    /// Probability a pipe pair has a pickup floating in its gap.
    var pickupChance: Float = 0.75
    /// Relative weights for coin / gem / star when a pickup spawns.
    var coinWeight: Float = 0.70
    var gemWeight: Float = 0.24
    var starWeight: Float = 0.06
    /// Probability the gap slides up and down.
    var movingChance: Float = 0
    var moveAmp: Float = 0.55
    var moveSpeed: Float = 1.1
    /// Probability the pipe lips grow hazard spikes into the gap.
    var spikeChance: Float = 0
}

// MARK: - Level

struct GameLevel: Identifiable, Equatable {
    var id: Int { index }

    let index: Int
    let name: String
    let tagline: String
    /// Pipes to pass to clear the level in campaign mode.
    let goalPipes: Int
    /// Score needed for the 2nd and 3rd star.
    let starTwo: Int
    let starThree: Int
    let tuning: LevelTuning
    let theme: LevelTheme

    static func == (lhs: GameLevel, rhs: GameLevel) -> Bool {
        lhs.index == rhs.index
    }
}

enum LevelCatalog {
    /// Pipes per themed stage while playing endless mode.
    static let endlessStageLength = 12

    static let all: [GameLevel] = makeLevels()

    static var count: Int { all.count }

    static func level(at index: Int) -> GameLevel {
        let i = max(0, min(all.count - 1, index))
        return all[i]
    }

    /// Endless mode cycles the campaign themes while difficulty keeps climbing.
    static func endlessStage(_ stage: Int) -> GameLevel {
        let s = max(0, stage)
        let base = all[s % all.count]
        let step = Float(s)

        var t = base.tuning
        t.pipeSpeed = min(base.tuning.pipeSpeed + step * 0.11, 6.2)
        t.pipeGap = max(base.tuning.pipeGap - step * 0.075, 2.62)
        t.pipeSpacing = max(base.tuning.pipeSpacing - step * 0.055, 3.5)
        t.movingChance = min(base.tuning.movingChance + step * 0.05, 0.75)
        t.moveAmp = min(base.tuning.moveAmp + step * 0.03, 1.15)
        t.spikeChance = min(base.tuning.spikeChance + step * 0.035, 0.4)
        t.gemWeight = min(base.tuning.gemWeight + step * 0.01, 0.35)
        t.starWeight = min(base.tuning.starWeight + step * 0.006, 0.16)

        let lap = s / all.count
        let name = lap > 0 ? "\(base.name) II" : base.name
        return GameLevel(
            index: s,
            name: name,
            tagline: base.tagline,
            goalPipes: endlessStageLength,
            starTwo: base.starTwo,
            starThree: base.starThree,
            tuning: t,
            theme: base.theme
        )
    }

    // MARK: Level definitions

    private static func makeLevels() -> [GameLevel] {
        [
            GameLevel(
                index: 0,
                name: "Meadow Day",
                tagline: "Warm sun, easy air.",
                goalPipes: 12,
                starTwo: 20,
                starThree: 27,
                tuning: meadowTuning(),
                theme: meadowTheme()
            ),
            GameLevel(
                index: 1,
                name: "Golden Dunes",
                tagline: "Desert thermals and cacti.",
                goalPipes: 13,
                starTwo: 22,
                starThree: 30,
                tuning: dunesTuning(),
                theme: dunesTheme()
            ),
            GameLevel(
                index: 2,
                name: "Coral Sunset",
                tagline: "Long shadows over the reef.",
                goalPipes: 14,
                starTwo: 24,
                starThree: 32,
                tuning: sunsetTuning(),
                theme: sunsetTheme()
            ),
            GameLevel(
                index: 3,
                name: "Frosted Peak",
                tagline: "Thin air. The gaps drift.",
                goalPipes: 15,
                starTwo: 26,
                starThree: 35,
                tuning: frostTuning(),
                theme: frostTheme()
            ),
            GameLevel(
                index: 4,
                name: "Midnight Sky",
                tagline: "Fireflies, moonlight, spikes.",
                goalPipes: 16,
                starTwo: 28,
                starThree: 38,
                tuning: midnightTuning(),
                theme: midnightTheme()
            ),
            GameLevel(
                index: 5,
                name: "Neon City",
                tagline: "Full speed through the grid.",
                goalPipes: 18,
                starTwo: 32,
                starThree: 43,
                tuning: neonTuning(),
                theme: neonTheme()
            )
        ]
    }

    // MARK: Tuning

    private static func meadowTuning() -> LevelTuning {
        var t = LevelTuning()
        t.pipeSpeed = 2.95
        t.pipeGap = 3.85
        t.pipeSpacing = 4.7
        t.pickupChance = 0.80
        return t
    }

    private static func dunesTuning() -> LevelTuning {
        var t = LevelTuning()
        t.pipeSpeed = 3.20
        t.pipeGap = 3.65
        t.pipeSpacing = 4.5
        t.pickupChance = 0.78
        t.gemWeight = 0.28
        return t
    }

    private static func sunsetTuning() -> LevelTuning {
        var t = LevelTuning()
        t.pipeSpeed = 3.45
        t.pipeGap = 3.50
        t.pipeSpacing = 4.35
        t.pickupChance = 0.74
        t.gemWeight = 0.30
        t.starWeight = 0.08
        t.movingChance = 0.18
        t.moveAmp = 0.45
        t.moveSpeed = 1.0
        return t
    }

    private static func frostTuning() -> LevelTuning {
        var t = LevelTuning()
        t.pipeSpeed = 3.70
        t.pipeGap = 3.35
        t.pipeSpacing = 4.25
        t.pickupChance = 0.72
        t.gemWeight = 0.30
        t.starWeight = 0.09
        t.movingChance = 0.40
        t.moveAmp = 0.70
        t.moveSpeed = 1.15
        t.spikeChance = 0.10
        return t
    }

    private static func midnightTuning() -> LevelTuning {
        var t = LevelTuning()
        t.pipeSpeed = 3.95
        t.pipeGap = 3.20
        t.pipeSpacing = 4.15
        t.pickupChance = 0.70
        t.gemWeight = 0.32
        t.starWeight = 0.11
        t.movingChance = 0.50
        t.moveAmp = 0.85
        t.moveSpeed = 1.30
        t.spikeChance = 0.22
        return t
    }

    private static func neonTuning() -> LevelTuning {
        var t = LevelTuning()
        t.pipeSpeed = 4.30
        t.pipeGap = 3.05
        t.pipeSpacing = 4.05
        t.pickupChance = 0.68
        t.gemWeight = 0.34
        t.starWeight = 0.13
        t.movingChance = 0.62
        t.moveAmp = 1.00
        t.moveSpeed = 1.45
        t.spikeChance = 0.32
        return t
    }

    // MARK: Themes

    private static func meadowTheme() -> LevelTheme {
        LevelTheme()
    }

    private static func dunesTheme() -> LevelTheme {
        var t = LevelTheme()
        t.skyTop = rgb(0.20, 0.46, 0.82)
        t.skyMid = rgb(0.62, 0.78, 0.93)
        t.skyHorizon = rgb(0.97, 0.87, 0.66)
        t.sunColor = rgb(1.00, 0.95, 0.74)
        t.sunPosition = SIMD2<Float>(0.50, 0.90)
        t.sunSize = 0.036
        t.cloudColor = rgb(1.00, 0.96, 0.88)
        t.cloudDensity = 0.34

        t.hillFar = rgb(0.66, 0.50, 0.32)
        t.hillMid = rgb(0.80, 0.62, 0.38)
        t.hillNear = rgb(0.90, 0.74, 0.46)
        t.hillCap = rgb(0.96, 0.84, 0.56)
        t.hillCapLine = 1.6
        t.groundTop = rgb(0.94, 0.80, 0.52)
        t.groundBody = rgb(0.70, 0.53, 0.30)
        t.groundStripe = rgb(0.86, 0.70, 0.42)

        t.pipeBody = rgb(0.84, 0.46, 0.20)
        t.pipeLip = rgb(0.96, 0.64, 0.30)

        t.fogColor = rgb(0.96, 0.86, 0.68)
        t.fogDensity = 0.026
        t.accent = rgb(1.00, 0.72, 0.20)
        t.ambient = 0.50
        t.lightColor = rgb(1.10, 1.00, 0.86)
        t.lightDir = SIMD3<Float>(-0.15, -0.94, -0.30)
        t.vignette = 0.32

        t.birdBody = rgb(1.00, 0.78, 0.18)
        t.birdWing = rgb(0.92, 0.55, 0.14)
        t.birdBeak = rgb(0.98, 0.40, 0.12)

        t.decor = .cactus
        t.decorColor = rgb(0.30, 0.56, 0.30)
        t.decorTrunk = rgb(0.26, 0.48, 0.26)
        t.ambientKind = .sand
        t.ambientColor = rgb(0.97, 0.86, 0.62)

        t.uiTop = rgb(0.98, 0.72, 0.30)
        t.uiBottom = rgb(0.55, 0.26, 0.10)
        return t
    }

    private static func sunsetTheme() -> LevelTheme {
        var t = LevelTheme()
        t.skyTop = rgb(0.20, 0.13, 0.44)
        t.skyMid = rgb(0.84, 0.34, 0.46)
        t.skyHorizon = rgb(1.00, 0.72, 0.36)
        t.sunColor = rgb(1.00, 0.60, 0.30)
        t.sunPosition = SIMD2<Float>(0.24, 0.32)
        t.sunSize = 0.070
        t.cloudColor = rgb(1.00, 0.70, 0.62)
        t.cloudDensity = 0.92
        t.starDensity = 0.18
        t.nightAmount = 0.25

        t.hillFar = rgb(0.24, 0.14, 0.34)
        t.hillMid = rgb(0.40, 0.20, 0.40)
        t.hillNear = rgb(0.58, 0.28, 0.42)
        t.hillCap = rgb(0.78, 0.40, 0.42)
        t.hillCapLine = 1.4
        t.groundTop = rgb(0.68, 0.34, 0.46)
        t.groundBody = rgb(0.30, 0.16, 0.28)
        t.groundStripe = rgb(0.52, 0.24, 0.38)

        t.pipeBody = rgb(0.20, 0.56, 0.58)
        t.pipeLip = rgb(0.42, 0.84, 0.78)
        t.pipeGlow = 0.10

        t.fogColor = rgb(0.94, 0.54, 0.42)
        t.fogDensity = 0.030
        t.accent = rgb(1.00, 0.56, 0.36)
        t.ambient = 0.38
        t.lightColor = rgb(1.15, 0.72, 0.58)
        t.lightDir = SIMD3<Float>(0.62, -0.62, -0.48)
        t.vignette = 0.42

        t.birdBody = rgb(1.00, 0.80, 0.34)
        t.birdBelly = rgb(1.00, 0.92, 0.78)
        t.birdWing = rgb(0.96, 0.52, 0.30)
        t.birdBeak = rgb(1.00, 0.42, 0.24)

        t.decor = .palm
        t.decorColor = rgb(0.18, 0.40, 0.34)
        t.decorTrunk = rgb(0.34, 0.20, 0.22)
        t.ambientKind = .petals
        t.ambientColor = rgb(1.00, 0.64, 0.62)

        t.uiTop = rgb(1.00, 0.52, 0.42)
        t.uiBottom = rgb(0.30, 0.10, 0.40)
        return t
    }

    private static func frostTheme() -> LevelTheme {
        var t = LevelTheme()
        t.skyTop = rgb(0.26, 0.48, 0.80)
        t.skyMid = rgb(0.60, 0.79, 0.95)
        t.skyHorizon = rgb(0.92, 0.96, 1.00)
        t.sunColor = rgb(0.96, 0.98, 1.00)
        t.sunPosition = SIMD2<Float>(0.70, 0.88)
        t.sunSize = 0.028
        t.cloudColor = rgb(1.00, 1.00, 1.00)
        t.cloudDensity = 1.00

        t.hillFar = rgb(0.46, 0.57, 0.74)
        t.hillMid = rgb(0.62, 0.74, 0.87)
        t.hillNear = rgb(0.76, 0.86, 0.95)
        t.hillCap = rgb(0.98, 1.00, 1.00)
        t.hillCapLine = 0.9
        t.groundTop = rgb(0.94, 0.97, 1.00)
        t.groundBody = rgb(0.52, 0.60, 0.72)
        t.groundStripe = rgb(0.84, 0.91, 0.99)

        t.pipeBody = rgb(0.26, 0.62, 0.80)
        t.pipeLip = rgb(0.62, 0.90, 0.98)
        t.pipeGlow = 0.18

        t.fogColor = rgb(0.88, 0.94, 1.00)
        t.fogDensity = 0.034
        t.accent = rgb(0.55, 0.90, 1.00)
        t.ambient = 0.52
        t.lightColor = rgb(0.95, 0.99, 1.10)
        t.lightDir = SIMD3<Float>(-0.35, -0.86, -0.38)
        t.vignette = 0.30

        t.birdBody = rgb(1.00, 0.86, 0.26)
        t.birdWing = rgb(0.98, 0.62, 0.22)

        t.decor = .pine
        t.decorColor = rgb(0.16, 0.36, 0.30)
        t.decorTrunk = rgb(0.34, 0.26, 0.22)
        t.ambientKind = .snow
        t.ambientColor = rgb(1.00, 1.00, 1.00)

        t.uiTop = rgb(0.60, 0.86, 1.00)
        t.uiBottom = rgb(0.12, 0.32, 0.58)
        return t
    }

    private static func midnightTheme() -> LevelTheme {
        var t = LevelTheme()
        t.skyTop = rgb(0.025, 0.035, 0.13)
        t.skyMid = rgb(0.07, 0.10, 0.28)
        t.skyHorizon = rgb(0.22, 0.19, 0.44)
        t.sunColor = rgb(0.92, 0.95, 1.00)
        t.sunPosition = SIMD2<Float>(0.74, 0.83)
        t.sunSize = 0.048
        t.cloudColor = rgb(0.26, 0.30, 0.52)
        t.cloudDensity = 0.48
        t.starDensity = 1.00
        t.nightAmount = 1.00

        t.hillFar = rgb(0.055, 0.075, 0.19)
        t.hillMid = rgb(0.09, 0.12, 0.27)
        t.hillNear = rgb(0.14, 0.17, 0.35)
        t.hillCap = rgb(0.24, 0.28, 0.48)
        t.hillCapLine = 1.5
        t.groundTop = rgb(0.13, 0.28, 0.27)
        t.groundBody = rgb(0.07, 0.11, 0.16)
        t.groundStripe = rgb(0.10, 0.24, 0.24)

        t.pipeBody = rgb(0.13, 0.30, 0.40)
        t.pipeLip = rgb(0.28, 0.88, 0.80)
        t.pipeGlow = 0.60

        t.fogColor = rgb(0.09, 0.11, 0.27)
        t.fogDensity = 0.036
        t.accent = rgb(0.42, 0.95, 0.86)
        t.ambient = 0.24
        t.lightColor = rgb(0.55, 0.64, 0.98)
        t.lightDir = SIMD3<Float>(-0.42, -0.80, -0.42)
        t.exposure = 1.12
        t.vignette = 0.52

        t.birdBody = rgb(1.00, 0.86, 0.30)
        t.birdBelly = rgb(1.00, 0.94, 0.72)
        t.birdWing = rgb(0.98, 0.64, 0.22)

        t.decor = .crystal
        t.decorColor = rgb(0.30, 0.80, 0.86)
        t.decorTrunk = rgb(0.12, 0.20, 0.32)
        t.decorGlow = 0.55
        t.ambientKind = .fireflies
        t.ambientColor = rgb(0.72, 1.00, 0.62)

        t.uiTop = rgb(0.30, 0.72, 0.86)
        t.uiBottom = rgb(0.04, 0.06, 0.20)
        return t
    }

    private static func neonTheme() -> LevelTheme {
        var t = LevelTheme()
        t.skyTop = rgb(0.045, 0.020, 0.16)
        t.skyMid = rgb(0.24, 0.06, 0.42)
        t.skyHorizon = rgb(0.74, 0.14, 0.52)
        t.sunColor = rgb(1.00, 0.30, 0.62)
        t.sunPosition = SIMD2<Float>(0.50, 0.26)
        t.sunSize = 0.115
        t.cloudColor = rgb(0.48, 0.14, 0.48)
        t.cloudDensity = 0.42
        t.starDensity = 0.70
        t.nightAmount = 0.88

        t.hillFar = rgb(0.09, 0.035, 0.22)
        t.hillMid = rgb(0.15, 0.05, 0.32)
        t.hillNear = rgb(0.22, 0.07, 0.42)
        t.hillCap = rgb(0.60, 0.14, 0.60)
        t.hillCapLine = 1.7
        t.groundTop = rgb(0.10, 0.04, 0.20)
        t.groundBody = rgb(0.06, 0.02, 0.13)
        t.groundStripe = rgb(0.95, 0.22, 0.74)
        t.groundGlow = 0.85

        t.pipeBody = rgb(0.14, 0.09, 0.34)
        t.pipeLip = rgb(0.20, 0.95, 1.00)
        t.pipeGlow = 0.90

        t.fogColor = rgb(0.28, 0.06, 0.36)
        t.fogDensity = 0.032
        t.accent = rgb(0.20, 0.95, 1.00)
        t.ambient = 0.28
        t.lightColor = rgb(0.95, 0.42, 1.05)
        t.lightDir = SIMD3<Float>(0.30, -0.82, -0.48)
        t.exposure = 1.18
        t.vignette = 0.55

        t.birdBody = rgb(1.00, 0.88, 0.24)
        t.birdBelly = rgb(1.00, 0.96, 0.80)
        t.birdWing = rgb(1.00, 0.42, 0.72)
        t.birdBeak = rgb(1.00, 0.34, 0.52)

        t.decor = .building
        t.decorColor = rgb(0.10, 0.05, 0.24)
        t.decorTrunk = rgb(0.95, 0.20, 0.70)
        t.decorGlow = 0.80
        t.ambientKind = .sparks
        t.ambientColor = rgb(0.35, 0.95, 1.00)

        t.uiTop = rgb(1.00, 0.24, 0.66)
        t.uiBottom = rgb(0.10, 0.02, 0.30)
        return t
    }
}

// MARK: - Persistence

/// Campaign progress and records, backed by `UserDefaults`.
@MainActor
@Observable
final class ScoreStore {
    private enum Key {
        static let stars = "level.stars.v2"
        static let best = "level.best.v2"
        static let unlocked = "level.unlocked.v2"
        static let endlessBest = "endless.best.v2"
        static let endlessStage = "endless.stage.v2"
        static let coins = "total.coins.v2"
        static let legacyHigh = "highScore"
    }

    private(set) var stars: [Int]
    private(set) var bests: [Int]
    private(set) var unlockedCount: Int
    private(set) var endlessBest: Int
    private(set) var endlessBestStage: Int
    private(set) var totalCoins: Int

    var totalStars: Int { stars.reduce(0, +) }
    var maxStars: Int { LevelCatalog.count * 3 }

    /// Highest level the player can jump straight into.
    var furthestUnlocked: Int { max(0, min(LevelCatalog.count - 1, unlockedCount - 1)) }

    init() {
        let defaults = UserDefaults.standard
        let n = LevelCatalog.count

        let savedStars = defaults.array(forKey: Key.stars) as? [Int] ?? []
        let savedBests = defaults.array(forKey: Key.best) as? [Int] ?? []
        stars = ScoreStore.fit(savedStars, to: n)
        bests = ScoreStore.fit(savedBests, to: n)

        unlockedCount = max(1, min(n, defaults.integer(forKey: Key.unlocked)))
        endlessBest = defaults.integer(forKey: Key.endlessBest)
        endlessBestStage = defaults.integer(forKey: Key.endlessStage)
        totalCoins = defaults.integer(forKey: Key.coins)

        // Carry over the score from the pre-levels build so returning players
        // keep their record.
        let legacy = defaults.integer(forKey: Key.legacyHigh)
        if legacy > endlessBest {
            endlessBest = legacy
            defaults.set(endlessBest, forKey: Key.endlessBest)
        }
    }

    private static func fit(_ values: [Int], to count: Int) -> [Int] {
        var out = Array(repeating: 0, count: count)
        for i in 0..<min(count, values.count) {
            out[i] = values[i]
        }
        return out
    }

    func isUnlocked(_ index: Int) -> Bool {
        index < unlockedCount
    }

    func stars(for index: Int) -> Int {
        guard index >= 0 && index < stars.count else { return 0 }
        return stars[index]
    }

    func best(for index: Int) -> Int {
        guard index >= 0 && index < bests.count else { return 0 }
        return bests[index]
    }

    /// Records a finished campaign run. Returns true when a new level unlocked.
    @discardableResult
    func recordCampaign(level: Int, score: Int, starsEarned: Int, cleared: Bool) -> Bool {
        guard level >= 0 && level < LevelCatalog.count else { return false }
        let defaults = UserDefaults.standard

        if score > bests[level] {
            bests[level] = score
            defaults.set(bests, forKey: Key.best)
        }
        if starsEarned > stars[level] {
            stars[level] = starsEarned
            defaults.set(stars, forKey: Key.stars)
        }

        var unlockedSomething = false
        if cleared && level + 1 >= unlockedCount && level + 1 < LevelCatalog.count {
            unlockedCount = level + 2
            defaults.set(unlockedCount, forKey: Key.unlocked)
            unlockedSomething = true
        }
        return unlockedSomething
    }

    func recordEndless(score: Int, stage: Int) {
        let defaults = UserDefaults.standard
        if score > endlessBest {
            endlessBest = score
            defaults.set(endlessBest, forKey: Key.endlessBest)
            defaults.set(endlessBest, forKey: Key.legacyHigh)
        }
        if stage > endlessBestStage {
            endlessBestStage = stage
            defaults.set(endlessBestStage, forKey: Key.endlessStage)
        }
    }

    func addCoins(_ amount: Int) {
        guard amount > 0 else { return }
        totalCoins += amount
        UserDefaults.standard.set(totalCoins, forKey: Key.coins)
    }

    func resetProgress() {
        let defaults = UserDefaults.standard
        stars = Array(repeating: 0, count: LevelCatalog.count)
        bests = Array(repeating: 0, count: LevelCatalog.count)
        unlockedCount = 1
        defaults.set(stars, forKey: Key.stars)
        defaults.set(bests, forKey: Key.best)
        defaults.set(unlockedCount, forKey: Key.unlocked)
    }
}
