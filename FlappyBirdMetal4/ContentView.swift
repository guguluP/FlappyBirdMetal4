import SwiftUI

struct ContentView: View {
    @State private var score = 0
    @State private var highScore = UserDefaults.standard.integer(forKey: "highScore")
    @State private var coins = 0
    @State private var phase: GamePhase = .ready
    @State private var coach = AppleIntelligenceCoach()
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ZStack {
            MetalGameView(
                score: $score,
                highScore: $highScore,
                coins: $coins,
                phase: $phase
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topHUD
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 10)

                Spacer()

                if phase != .playing {
                    overlayCard
                        .padding(.horizontal, horizontalPadding)
                        .padding(.bottom, 36)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: phase)
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 640)
        #endif
        #if os(iOS)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        #endif
        .onAppear {
            coach.refreshAvailability()
            coach.refreshForPhase(phase, score: score, coins: coins, highScore: highScore)
        }
        .onChange(of: phase) { _, newPhase in
            coach.refreshForPhase(newPhase, score: score, coins: coins, highScore: highScore)
        }
    }

    private var horizontalPadding: CGFloat {
        #if os(iOS)
        sizeClass == .compact ? 16 : 28
        #else
        20
        #endif
    }

    private var topHUD: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("SCORE \(score)")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Label("\(coins)", systemImage: "circle.fill")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 1, green: 0.84, blue: 0.2))
                    .shadow(color: .black.opacity(0.45), radius: 2, y: 1)

                Spacer(minLength: 4)

                Text("BEST \(highScore)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }

            if coach.isAppleIntelligenceAvailable {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                    Text(coach.badgeLabel)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(.ultraThinMaterial.opacity(0.55)))
            }
        }
    }

    @ViewBuilder
    private var overlayCard: some View {
        VStack(spacing: 12) {
            Text(titleText)
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(subtitleText)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)

            if phase == .gameOver {
                Text("Coins this run: \(coins)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 1, green: 0.84, blue: 0.2))
            }

            coachPanel

            Text(platformFooter)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: 420)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.black.opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
        )
    }

    private var coachPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: coach.isAppleIntelligenceAvailable ? "sparkles" : "lightbulb.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text(coach.isAppleIntelligenceAvailable ? "Apple Intelligence Coach" : "Coach")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                if coach.isGenerating {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white.opacity(0.9))

            Text(coach.coachLine.isEmpty ? "…" : coach.coachLine)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.95))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if case .unavailable(let reason) = coach.supportState, phase == .ready {
                Text(reason)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.08))
        )
    }

    private var platformFooter: String {
        #if os(macOS)
        "Metal 4 · 3D · Mac & iPhone"
        #else
        "Metal 4 · 3D · iPhone"
        #endif
    }

    private var titleText: String {
        switch phase {
        case .ready: return "FLAPPY 3D"
        case .playing: return ""
        case .gameOver: return "GAME OVER"
        }
    }

    private var subtitleText: String {
        switch phase {
        case .ready:
            #if os(macOS)
            return "Click or press Space to flap\nCollect spinning gold rings (+2)"
            #else
            return "Tap anywhere to flap\nCollect spinning gold rings (+2)"
            #endif
        case .playing:
            return ""
        case .gameOver:
            #if os(macOS)
            return "Click or Space to try again"
            #else
            return "Tap to try again"
            #endif
        }
    }
}

#Preview {
    ContentView()
}
