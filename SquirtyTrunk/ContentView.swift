import SwiftUI
import AVFoundation
import Combine

// MARK: - Sound Manager
class SoundManager {
    static let shared = SoundManager()
    var soundOn = true
    func play(_ id: SystemSoundID) {
        if soundOn { AudioServicesPlaySystemSound(id) }
    }
    func sprayHit() { play(1057) }
    func rescue() { play(1025) }
    func hurt() { play(1053) }
    func gameOver() { play(1006) }
}

// MARK: - Game State
class GameState: ObservableObject {
    @Published var score = 0
    @Published var babiesRescued = 0
    @Published var bestScore = UserDefaults.standard.integer(forKey: "bestBabiesSquirty")
    @Published var lives = 3
    @Published var isGameOver = false

    func reset() {
        score = 0
        babiesRescued = 0
        lives = 3
        isGameOver = false
    }

    func saveBest() {
        if babiesRescued > bestScore {
            bestScore = babiesRescued
            UserDefaults.standard.set(bestScore, forKey: "bestBabiesSquirty")
        }
    }
}

// MARK: - Entities
struct Rock: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var targetingBaby: Bool   // true if falling toward a baby's lane
}

struct BabyElephant: Identifiable {
    let id = UUID()
    var x: CGFloat
    var fromLeft: Bool
    var rescued: Bool = false
}

// MARK: - Root View
struct ContentView: View {
    @State private var screen: Screen = .menu
    @StateObject private var game = GameState()

    enum Screen { case menu, playing, gameOver, scores, settings }

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.15, blue: 0.18).ignoresSafeArea()

            switch screen {
            case .menu:
                MenuView(screen: $screen)
            case .playing:
                GameView(screen: $screen, game: game)
            case .gameOver:
                GameOverView(screen: $screen, game: game)
            case .scores:
                ScoresView(screen: $screen, game: game)
            case .settings:
                SettingsView(screen: $screen)
            }
        }
    }
}

// MARK: - Icon Button (compact, icon-only, no overflow)
struct IconButton: View {
    let systemIcon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemIcon)
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 64, height: 64)
                .background(
                    Circle()
                        .fill(color)
                        .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 2))
                        .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 4)
                )
        }
    }
}

// MARK: - Menu
struct MenuView: View {
    @Binding var screen: ContentView.Screen
    @State private var sprayBounce = false

    var body: some View {
        ZStack {
            Image("Background")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.45))

            VStack(spacing: 30) {
            Spacer()

            Text("SQUIRTY TRUNK")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .tracking(2)

            Image("elephant")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)

            Spacer()

            HStack(spacing: 24) {
                IconButton(systemIcon: "trophy.fill", color: Color(red: 0.85, green: 0.4, blue: 0.2)) {
                    screen = .scores
                }
                IconButton(systemIcon: "play.fill", color: Color(red: 0.0, green: 0.45, blue: 0.45)) {
                    screen = .playing
                }
                IconButton(systemIcon: "gearshape.fill", color: Color(red: 0.45, green: 0.25, blue: 0.55)) {
                    screen = .settings
                }
            }
            .padding(.bottom, 50)
            }
        }
    }
}

// MARK: - Game View
struct GameView: View {
    @Binding var screen: ContentView.Screen
    @ObservedObject var game: GameState

    @State private var elephantX: CGFloat = 0.5   // 0...1 normalized
    @State private var rocks: [Rock] = []
    @State private var babies: [BabyElephant] = []
    @State private var sprayActive = false
    @State private var sprayDirection: CGFloat = 0
    @State private var rescueFlash = false
    @State private var hitFlash = false
    @State private var timer: Timer?
    @State private var spawnTick = 0
    @State private var showQuitConfirm = false

    let groundY: CGFloat = 0.82  // normalized ground line

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                Image("Background")
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: h)
                    .clipped()
                    .position(x: w/2, y: h/2)
                    .ignoresSafeArea()

                // Tap layer for movement - sits above background but below HUD buttons
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: w, height: h)
                    .onTapGesture { location in
                        handleTap(location: location, width: w)
                    }

                // HUD - centered
                VStack {
                    HStack {
                        HStack(spacing: 4) {
                            ForEach(0..<3) { i in
                                Image(systemName: i < game.lives ? "heart.fill" : "heart")
                                    .foregroundColor(.red)
                            }
                        }
                        Spacer()
                        VStack(spacing: 2) {
                            Text("\(game.score)")
                                .font(.system(size: 26, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                                .monospacedDigit()
                            HStack(spacing: 4) {
                                Image(systemName: "pawprint.fill").font(.system(size: 12))
                                Text("\(game.babiesRescued)")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.yellow)
                        }
                        Spacer()
                        IconButton(systemIcon: "xmark", color: Color.black.opacity(0.5)) {
                            timer?.invalidate()
                            timer = nil
                            showQuitConfirm = true
                        }
                        .scaleEffect(0.6)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 55)
                    Spacer()
                }

                // Baby elephants walking on ground
                ForEach(babies) { baby in
                    Image("babyElephant")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60, height: 60)
                        .scaleEffect(x: baby.fromLeft ? 1 : -1, y: 1)
                        .position(x: baby.x, y: h * groundY)
                        .onTapGesture { rescueBaby(baby) }
                }

                // Rocks falling
                ForEach(rocks) { rock in
                    Image("rock")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                        .position(x: rock.x, y: rock.y)
                }

                // Adult elephant
                Image("elephant")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 110, height: 110)
                    .scaleEffect(x: sprayDirection < 0 ? -1 : 1, y: 1)
                    .position(x: elephantX * w, y: h * groundY - 10)

                // Spray effect - trunk tip se seedha upar
                if sprayActive {
                    Image("waterSpray")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .position(x: elephantX * w, y: h * groundY - 145)
                    Image("waterSpray")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 50, height: 50)
                        .opacity(0.6)
                        .position(x: elephantX * w + (sprayDirection * 20), y: h * groundY - 200)
                }

                // Feedback flashes
                if rescueFlash {
                    Text("🎉 RESCUED!")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundColor(.yellow)
                        .position(x: w/2, y: h * 0.3)
                        .transition(.opacity)
                }
                if hitFlash {
                    Text("-1")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundColor(.red)
                        .position(x: elephantX * w, y: h * groundY - 80)
                        .transition(.opacity)
                }

                if showQuitConfirm {
                    ZStack {
                        Color.black.opacity(0.6)
                            .ignoresSafeArea()
                            .onTapGesture { }

                        VStack(spacing: 22) {
                            Text("Quit Game?")
                                .font(.system(size: 22, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                            Text("Your progress will be lost.")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))

                            HStack(spacing: 20) {
                                Button(action: {
                                    showQuitConfirm = false
                                    // resume timer without resetting game state
                                    timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                                        tick(width: w)
                                    }
                                }) {
                                    Text("Continue")
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                        .padding(.vertical, 12)
                                        .padding(.horizontal, 20)
                                        .background(Capsule().fill(Color(red: 0.0, green: 0.45, blue: 0.45)))
                                }
                                Button(action: {
                                    showQuitConfirm = false
                                    stopGame()
                                    screen = .menu
                                }) {
                                    Text("Quit")
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                        .padding(.vertical, 12)
                                        .padding(.horizontal, 24)
                                        .background(Capsule().fill(Color.red.opacity(0.8)))
                                }
                            }
                        }
                        .padding(28)
                        .background(
                            RoundedRectangle(cornerRadius: 24)
                                .fill(Color(red: 0.05, green: 0.15, blue: 0.18))
                                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.2), lineWidth: 1))
                        )
                    }
                    .position(x: w/2, y: h/2)
                    .transition(.opacity)
                }
            }
            .onAppear { startGame(width: w) }
            .onDisappear { stopGame() }
            .onChange(of: game.isGameOver) { over in
                if over {
                    stopGame()
                    game.saveBest()
                    screen = .gameOver
                }
            }
        }
        .ignoresSafeArea()
    }

    func handleTap(location: CGPoint, width: CGFloat) {
        let half = width / 2
        if location.x < half {
            elephantX = max(0.08, elephantX - 0.08)
            sprayDirection = -1
        } else {
            elephantX = min(0.92, elephantX + 0.08)
            sprayDirection = 1
        }
        triggerSpray(width: width)
    }

    func triggerSpray(width: CGFloat) {
        sprayActive = true
        SoundManager.shared.sprayHit()
        let elephantPixelX = elephantX * width
        let groundPixelY = UIScreen.main.bounds.height * groundY

        // destroy rocks above elephant within horizontal range
        rocks.removeAll { rock in
            let withinX = abs(rock.x - elephantPixelX) < 100
            let aboveGround = rock.y < groundPixelY
            return withinX && aboveGround
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            sprayActive = false
        }
    }

    func rescueBaby(_ baby: BabyElephant) {
        guard let idx = babies.firstIndex(where: { $0.id == baby.id }) else { return }
        babies.remove(at: idx)
        game.score += 3
        game.babiesRescued += 1
        SoundManager.shared.rescue()
        withAnimation { rescueFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation { rescueFlash = false }
        }
    }

    func startGame(width: CGFloat) {
        game.reset()
        elephantX = 0.5
        rocks = []
        babies = []
        spawnTick = 0

        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            tick(width: width)
        }
    }

    func stopGame() {
        timer?.invalidate()
        timer = nil
    }

    func tick(width: CGFloat) {
        spawnTick += 1

        // move rocks down
        for i in rocks.indices { rocks[i].y += 3.5 + CGFloat(game.score) * 0.02 }

        let groundPixelY = UIScreen.main.bounds.height * groundY

        // check rock collisions
        var rocksToRemove: [UUID] = []
        for rock in rocks {
            if rock.y >= groundPixelY - 20 {
                let elephantPixelX = elephantX * width
                let hitAdult = abs(rock.x - elephantPixelX) < 55
                let hitBaby = babies.contains { abs($0.x - rock.x) < 40 }

                if hitBaby {
                    rocksToRemove.append(rock.id)
                    game.lives -= 1
                    SoundManager.shared.hurt()
                    withAnimation { hitFlash = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        withAnimation { hitFlash = false }
                    }
                    if game.lives <= 0 { game.isGameOver = true }
                } else if hitAdult {
                    rocksToRemove.append(rock.id)
                    game.lives -= 1
                    SoundManager.shared.hurt()
                    withAnimation { hitFlash = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        withAnimation { hitFlash = false }
                    }
                    if game.lives <= 0 { game.isGameOver = true }
                } else {
                    rocksToRemove.append(rock.id)
                }
            }
        }
        rocks.removeAll { rocksToRemove.contains($0.id) }

        // move babies forward toward center
        for i in babies.indices {
            babies[i].x += babies[i].fromLeft ? 1.4 : -1.4
        }
        // babies that successfully cross the screen also count as saved
        let crossed = babies.filter { $0.x > width + 40 }
        if !crossed.isEmpty {
            game.score += crossed.count * 3
            game.babiesRescued += crossed.count
        }
        babies.removeAll { $0.x < -40 || $0.x > width + 40 }

        // spawn rocks
        if spawnTick % max(18 - game.score / 10, 8) == 0 {
            let x = CGFloat.random(in: 40...(width - 40))
            // spawn from upper-mid screen so spray can reach before ground
            let startY = UIScreen.main.bounds.height * 0.25
            rocks.append(Rock(x: x, y: startY, targetingBaby: false))
        }

        // spawn babies - always from left, walking right across screen
        if spawnTick % 70 == 0 {
            babies.append(BabyElephant(x: -30, fromLeft: true))
        }
    }
}

// MARK: - Game Over
struct GameOverView: View {
    @Binding var screen: ContentView.Screen
    @ObservedObject var game: GameState

    var body: some View {
        ZStack {
            Image("Background")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.45))

            VStack(spacing: 24) {
            Spacer()
            Text("GAME OVER")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundColor(.white)

            Image("elephant")
                .resizable()
                .scaledToFit()
                .frame(width: 130, height: 130)
                .colorMultiply(.gray)

            VStack(spacing: 8) {
                Text("Score: \(game.score)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill").foregroundColor(.yellow)
                    Text("Best Rescued: \(game.bestScore)")
                        .foregroundColor(.white)
                }
            }

            Spacer()

            HStack(spacing: 24) {
                IconButton(systemIcon: "house.fill", color: Color(red: 0.45, green: 0.25, blue: 0.55)) {
                    screen = .menu
                }
                IconButton(systemIcon: "arrow.clockwise", color: Color(red: 0.0, green: 0.45, blue: 0.45)) {
                    screen = .playing
                }
            }
            .padding(.bottom, 50)
            }
        }
    }
}

// MARK: - Scores
struct ScoresView: View {
    @Binding var screen: ContentView.Screen
    @ObservedObject var game: GameState

    var body: some View {
        ZStack {
            Image("Background")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.45))

            VStack(spacing: 30) {
                Spacer()
                Image(systemName: "trophy.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.yellow)
                Text("BABIES RESCUED")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                Text("\(game.bestScore)")
                    .font(.system(size: 50, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                IconButton(systemIcon: "chevron.left", color: Color(red: 0.85, green: 0.4, blue: 0.2)) {
                    screen = .menu
                }
                .padding(.bottom, 50)
            }
        }
    }
}

// MARK: - Settings
struct SettingsView: View {
    @Binding var screen: ContentView.Screen
    @State private var soundOn = SoundManager.shared.soundOn

    var body: some View {
        ZStack {
            Image("Background")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.45))

            VStack(spacing: 30) {
            Spacer()
            Image(systemName: "gearshape.fill")
                .font(.system(size: 40))
                .foregroundColor(.white)

            Toggle(isOn: $soundOn) {
                HStack {
                    Image(systemName: "speaker.wave.2.fill")
                    Text("Sound")
                }
                .foregroundColor(.white)
            }
            .padding(.horizontal, 50)
            .onChange(of: soundOn) { val in SoundManager.shared.soundOn = val }

            VStack(alignment: .leading, spacing: 14) {
                HStack { Image(systemName: "hand.tap.fill"); Text("Tap left/right side to move + spray") }
                HStack { Image(systemName: "drop.fill"); Text("Spray destroys rocks") }
                HStack { Image(systemName: "figure.walk"); Text("Touch baby elephants to rescue") }
                HStack { Image(systemName: "exclamationmark.triangle.fill"); Text("Rock hits you = lose a life") }
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white.opacity(0.85))
            .padding(.horizontal, 30)

            Spacer()
            IconButton(systemIcon: "chevron.left", color: Color(red: 0.45, green: 0.25, blue: 0.55)) {
                screen = .menu
            }
            .padding(.bottom, 50)
            }
        }
    }
}

#Preview {
    ContentView()
}
