import SwiftUI
import MetalKit

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct MetalGameView: View {
    @Binding var score: Int
    @Binding var highScore: Int
    @Binding var coins: Int
    @Binding var phase: GamePhase

    var body: some View {
        MetalGameViewRepresentable(
            score: $score,
            highScore: $highScore,
            coins: $coins,
            phase: $phase
        )
    }
}

#if os(macOS)
struct MetalGameViewRepresentable: NSViewRepresentable {
    @Binding var score: Int
    @Binding var highScore: Int
    @Binding var coins: Int
    @Binding var phase: GamePhase

    func makeCoordinator() -> Coordinator {
        Coordinator(score: $score, highScore: $highScore, coins: $coins, phase: $phase)
    }

    func makeNSView(context: Context) -> InteractiveMTKView {
        let view = InteractiveMTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = MTLClearColor(red: 0.45, green: 0.75, blue: 0.95, alpha: 1)
        view.delegate = context.coordinator
        context.coordinator.attach(to: view)
        view.onTap = { [weak coordinator = context.coordinator] in
            coordinator?.renderer?.handleTap()
        }
        return view
    }

    func updateNSView(_ nsView: InteractiveMTKView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, MTKViewDelegate {
        var renderer: Metal4Renderer?
        private var score: Binding<Int>
        private var highScore: Binding<Int>
        private var coins: Binding<Int>
        private var phase: Binding<GamePhase>
        private var keyMonitor: Any?

        init(score: Binding<Int>, highScore: Binding<Int>, coins: Binding<Int>, phase: Binding<GamePhase>) {
            self.score = score
            self.highScore = highScore
            self.coins = coins
            self.phase = phase
        }

        func attach(to view: MTKView) {
            let r = Metal4Renderer(metalKitView: view)
            r?.onScoreChange = { [weak self] value in
                DispatchQueue.main.async {
                    self?.score.wrappedValue = value
                    if value > (self?.highScore.wrappedValue ?? 0) {
                        self?.highScore.wrappedValue = value
                        UserDefaults.standard.set(value, forKey: "highScore")
                    }
                }
            }
            r?.onCoinsChange = { [weak self] value in
                DispatchQueue.main.async {
                    self?.coins.wrappedValue = value
                }
            }
            r?.onPhaseChange = { [weak self] value in
                DispatchQueue.main.async {
                    self?.phase.wrappedValue = value
                }
            }
            renderer = r
            view.delegate = r

            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 49 { // Space
                    self?.renderer?.handleTap()
                    return nil
                }
                return event
            }
        }

        deinit {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
            }
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            renderer?.mtkView(view, drawableSizeWillChange: size)
        }

        func draw(in view: MTKView) {
            renderer?.draw(in: view)
        }
    }
}

final class InteractiveMTKView: MTKView {
    var onTap: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        onTap?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 {
            onTap?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }
}

#else

struct MetalGameViewRepresentable: UIViewRepresentable {
    @Binding var score: Int
    @Binding var highScore: Int
    @Binding var coins: Int
    @Binding var phase: GamePhase

    func makeCoordinator() -> Coordinator {
        Coordinator(score: $score, highScore: $highScore, coins: $coins, phase: $phase)
    }

    func makeUIView(context: Context) -> InteractiveMTKView {
        let view = InteractiveMTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = MTLClearColor(red: 0.45, green: 0.75, blue: 0.95, alpha: 1)
        view.isMultipleTouchEnabled = false
        context.coordinator.attach(to: view)
        view.onTap = { [weak coordinator = context.coordinator] in
            coordinator?.playHaptic()
            coordinator?.renderer?.handleTap()
        }
        return view
    }

    func updateUIView(_ uiView: InteractiveMTKView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject {
        var renderer: Metal4Renderer?
        private var score: Binding<Int>
        private var highScore: Binding<Int>
        private var coins: Binding<Int>
        private var phase: Binding<GamePhase>
        private let flapHaptic = UIImpactFeedbackGenerator(style: .light)

        init(score: Binding<Int>, highScore: Binding<Int>, coins: Binding<Int>, phase: Binding<GamePhase>) {
            self.score = score
            self.highScore = highScore
            self.coins = coins
            self.phase = phase
            flapHaptic.prepare()
        }

        func playHaptic() {
            flapHaptic.impactOccurred(intensity: 0.7)
            flapHaptic.prepare()
        }

        func attach(to view: MTKView) {
            let r = Metal4Renderer(metalKitView: view)
            r?.onScoreChange = { [weak self] value in
                DispatchQueue.main.async {
                    self?.score.wrappedValue = value
                    if value > (self?.highScore.wrappedValue ?? 0) {
                        self?.highScore.wrappedValue = value
                        UserDefaults.standard.set(value, forKey: "highScore")
                    }
                }
            }
            r?.onCoinsChange = { [weak self] value in
                DispatchQueue.main.async {
                    self?.coins.wrappedValue = value
                }
            }
            r?.onPhaseChange = { [weak self] value in
                DispatchQueue.main.async {
                    self?.phase.wrappedValue = value
                }
            }
            renderer = r
            view.delegate = r
        }
    }
}

final class InteractiveMTKView: MTKView {
    var onTap: (() -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        onTap?()
    }
}
#endif
