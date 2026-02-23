import SwiftUI
import SpriteKit

// MARK: - SnakeBusView

/// A full-screen SwiftUI wrapper that presents the Snake Bus SpriteKit Easter
/// Egg game. Designed to be displayed via `.fullScreenCover`.
struct SnakeBusView: View {

    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var scene: SnakeBusScene?
    @State private var score: Int = 0
    @State private var isGameOver: Bool = false

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height) - 32

            ZStack {
                // Background
                Color(white: 0.14)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // HUD bar at top
                    hudBar

                    Spacer()

                    // Square game area
                    ZStack {
                        if let scene {
                            SpriteView(scene: scene)
                                .frame(width: side, height: side)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        } else {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(white: 0.14))
                                .frame(width: side, height: side)
                        }
                    }

                    Spacer()
                }

                // Game over overlay
                if isGameOver {
                    gameOverOverlay
                        .transition(.opacity)
                }
            }
            .onAppear {
                setupScene(size: CGSize(width: side, height: side))
            }
            .animation(.easeInOut(duration: 0.35), value: isGameOver)
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }

    // MARK: - Scene Setup

    private func setupScene(size: CGSize) {
        let newScene = SnakeBusScene(size: size)
        newScene.scaleMode = .resizeFill

        newScene.onScoreChanged = { newScore in
            withAnimation(.snappy(duration: 0.15)) {
                score = newScore
            }
        }

        newScene.onGameOver = { finalScore in
            score = finalScore
            withAnimation {
                isGameOver = true
            }
        }

        scene = newScene
    }

    // MARK: - HUD Bar

    private var hudBar: some View {
        HStack(alignment: .top) {
            // Dismiss button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .padding(.leading, 16)

            Spacer()

            // Title
            VStack(spacing: 2) {
                Text("Linea 495")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                Text("Lo Snodato")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.top, 4)

            Spacer()

            // Score badge
            HStack(spacing: 5) {
                Image(systemName: "person.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(score)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
            .padding(.trailing, 16)
        }
        .padding(.top, 8)
    }

    // MARK: - Game Over Overlay

    private var gameOverOverlay: some View {
        ZStack {
            // Dimming background
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { } // absorb taps

            VStack(spacing: 20) {
                // Title
                Text("CAPOLINEA!")
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)

                // Subtitle
                Text("Fine della corsa per la linea 495")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))

                // Score card
                VStack(spacing: 8) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.yellow)

                    Text("\(score)")
                        .font(.system(size: 54, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)

                    Text("passeggeri raccolti")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .padding(.vertical, 20)

                // Action buttons
                VStack(spacing: 12) {
                    // Rigioca (play again)
                    Button {
                        restartGame()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 16, weight: .bold))
                            Text("Rigioca")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: 220)
                        .padding(.vertical, 14)
                        .background(
                            Color(red: 0xC1 / 255.0,
                                  green: 0x27 / 255.0,
                                  blue: 0x2D / 255.0),
                            in: .capsule
                        )
                    }

                    // Esci (exit)
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                            Text("Esci")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: 220)
                        .padding(.vertical, 12)
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                }
                .padding(.top, 4)
            }
            .padding(32)
        }
    }

    // MARK: - Restart

    private func restartGame() {
        isGameOver = false
        score = 0
        scene?.restartGame()
    }
}

// MARK: - Preview

#Preview {
    SnakeBusView()
}
