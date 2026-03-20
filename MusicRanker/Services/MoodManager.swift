import SwiftUI

/// Mood system — influences recommendations, UI colors, and animations
@MainActor
final class MoodManager: ObservableObject {

    // MARK: - Mood Definition

    enum Mood: String, CaseIterable, Identifiable {
        case none = "Aucun"
        case chill = "Chill"
        case party = "Party"
        case workout = "Workout"
        case love = "Love"
        case night = "Night"
        case nostalgia = "Nostalgia"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .none: "circle.dashed"
            case .chill: "leaf.fill"
            case .party: "party.popper.fill"
            case .workout: "flame.fill"
            case .love: "heart.fill"
            case .night: "moon.stars.fill"
            case .nostalgia: "clock.arrow.circlepath"
            }
        }

        var emoji: String {
            switch self {
            case .none: ""
            case .chill: "🍃"
            case .party: "🎉"
            case .workout: "🔥"
            case .love: "💕"
            case .night: "🌙"
            case .nostalgia: "✨"
            }
        }

        var gradient: [Color] {
            switch self {
            case .none: [.gray.opacity(0.3), .gray.opacity(0.1)]
            case .chill: [.teal, .cyan.opacity(0.6), .mint.opacity(0.3)]
            case .party: [.pink, .orange, .yellow.opacity(0.5)]
            case .workout: [.red, .orange, .yellow.opacity(0.4)]
            case .love: [.pink, .red.opacity(0.7), .purple.opacity(0.4)]
            case .night: [.indigo, .purple.opacity(0.6), .blue.opacity(0.3)]
            case .nostalgia: [.orange.opacity(0.8), .brown.opacity(0.5), .yellow.opacity(0.3)]
            }
        }

        var accentColor: Color {
            switch self {
            case .none: .white
            case .chill: .cyan
            case .party: .orange
            case .workout: .red
            case .love: .pink
            case .night: .indigo
            case .nostalgia: .orange
            }
        }

        /// Search terms to influence recommendations
        var searchTerms: [String] {
            switch self {
            case .none: []
            case .chill: ["chill lo-fi", "relax ambient", "calm acoustic", "soft vibes"]
            case .party: ["party hits", "dance floor", "club bangers", "festival anthems"]
            case .workout: ["workout motivation", "gym energy", "hype beats", "running music"]
            case .love: ["love songs", "romantic ballads", "slow dance", "feel good love"]
            case .night: ["late night vibes", "midnight drive", "dark ambient", "after hours"]
            case .nostalgia: ["throwback hits", "90s classics", "2000s nostalgia", "old school"]
            }
        }

        /// Energy range for this mood
        var energyRange: ClosedRange<Double> {
            switch self {
            case .none: 0...1
            case .chill: 0...0.4
            case .party: 0.6...1.0
            case .workout: 0.7...1.0
            case .love: 0.2...0.6
            case .night: 0.1...0.5
            case .nostalgia: 0.3...0.7
            }
        }
    }

    // MARK: - Published State

    @Published var currentMood: Mood = .none {
        didSet {
            if currentMood != .none {
                UserDefaults.standard.set(currentMood.rawValue, forKey: "vibely_mood")
            } else {
                UserDefaults.standard.removeObject(forKey: "vibely_mood")
            }
        }
    }

    @Published var showMoodPicker = false

    // MARK: - Init

    init() {
        if let saved = UserDefaults.standard.string(forKey: "vibely_mood"),
           let mood = Mood(rawValue: saved) {
            currentMood = mood
        }
    }

    // MARK: - Public

    var isActive: Bool { currentMood != .none }

    var activeMoods: [Mood] {
        Mood.allCases.filter { $0 != .none }
    }

    func selectMood(_ mood: Mood) {
        withAnimation(.spring(duration: 0.3)) {
            currentMood = (currentMood == mood) ? .none : mood
        }
        HapticManager.impact(.medium)
    }

    func clearMood() {
        withAnimation(.spring(duration: 0.3)) {
            currentMood = .none
        }
        HapticManager.selection()
    }
}
