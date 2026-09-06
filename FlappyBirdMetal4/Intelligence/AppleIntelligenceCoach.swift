import Foundation
import Observation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device coach powered by **Apple Intelligence** (`FoundationModels`).
/// On devices where the system model is unavailable, uses local fallback lines
/// so the game still works on all supported iPhones and Macs.
@MainActor
@Observable
final class AppleIntelligenceCoach {
    enum SupportState: Equatable {
        case checking
        case available
        case unavailable(String)
    }

    var supportState: SupportState = .checking
    var coachLine: String = ""
    var isGenerating = false
    var badgeLabel: String = "Coach"

    var isAppleIntelligenceAvailable: Bool {
        if case .available = supportState { return true }
        return false
    }

    #if canImport(FoundationModels)
    @ObservationIgnored
    private var session: LanguageModelSession?
    #endif

    private let fallbackReady = [
        "Tap the sky and thread the pipes. Gold rings are +2!",
        "Short flaps beat panic flaps. Stay in the middle.",
        "Ride the rhythm: flap, glide, collect the rings."
    ]

    private let fallbackGameOver = [
        "Nice try! Watch the gap center and flap earlier next run.",
        "Almost! Soft taps near the bottom keep you out of pipes.",
        "Great effort — grab rings for bonus points next time."
    ]

    init() {
        refreshAvailability()
    }

    func refreshAvailability() {
        #if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            supportState = .available
            badgeLabel = "Apple Intelligence"
            session = LanguageModelSession(
                model: model,
                instructions: """
                You are a cheerful, brief coach for a 3D Flappy Bird mobile game.
                Rules of the game: tap/click/space to flap; avoid pipes; collect gold rings for +2 points.
                Reply in one short sentence (max 18 words). No hashtags, no emojis overload (0–1 emoji max).
                Be encouraging and specific. Never mention being an AI model.
                """
            )
        case .unavailable(let reason):
            session = nil
            let message: String
            switch reason {
            case .deviceNotEligible:
                message = "This device doesn't support Apple Intelligence"
            case .appleIntelligenceNotEnabled:
                message = "Turn on Apple Intelligence in Settings to enable the coach"
            case .modelNotReady:
                message = "Apple Intelligence is downloading — coach uses offline tips"
            @unknown default:
                message = "Apple Intelligence unavailable — offline tips active"
            }
            supportState = .unavailable(message)
            badgeLabel = "Coach"
            if coachLine.isEmpty {
                coachLine = fallbackReady.randomElement() ?? fallbackReady[0]
            }
        }
        #else
        supportState = .unavailable("Foundation Models not linked")
        badgeLabel = "Coach"
        coachLine = fallbackReady.randomElement() ?? fallbackReady[0]
        #endif
    }

    /// Call when the ready or game-over overlay appears.
    func refreshForPhase(_ phase: GamePhase, score: Int, coins: Int, highScore: Int) {
        switch phase {
        case .ready:
            Task { await generateReadyTip() }
        case .gameOver:
            Task { await generateGameOverTip(score: score, coins: coins, highScore: highScore) }
        case .playing:
            break
        }
    }

    func generateReadyTip() async {
        let prompt = """
        Write a one-sentence tip for a player about to start Flappy Bird 3D.
        Mention tapping to flap and optionally gold rings. Keep it fun.
        """
        await generate(prompt: prompt, fallbackPool: fallbackReady)
    }

    func generateGameOverTip(score: Int, coins: Int, highScore: Int) async {
        let beat = score >= highScore && score > 0
        let prompt = """
        Player just finished a run: score \(score), coins \(coins), best \(highScore).
        \(beat ? "They tied or beat their best — celebrate briefly." : "Encourage them with one concrete tip.")
        One short sentence only.
        """
        await generate(prompt: prompt, fallbackPool: fallbackGameOver)
    }

    private func generate(prompt: String, fallbackPool: [String]) async {
        guard !isGenerating else { return }
        isGenerating = true
        defer { isGenerating = false }

        #if canImport(FoundationModels)
        if case .available = supportState, let session {
            do {
                let response = try await session.respond(to: prompt)
                let text = response.content
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\n", with: " ")
                if !text.isEmpty {
                    coachLine = String(text.prefix(160))
                    return
                }
            } catch {
                // Fall through to offline tips
            }
        }
        #endif

        coachLine = fallbackPool.randomElement() ?? fallbackPool[0]
    }
}
