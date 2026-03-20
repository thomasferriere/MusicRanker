import Foundation
import Combine

/// ViewModel for the Search feature
@MainActor
final class SearchViewModel: ObservableObject {

    // MARK: - Published

    @Published var query = ""
    @Published var results: [iTunesTrack] = []
    @Published var isSearching = false
    @Published var searchHistory: [String] = []
    @Published var suggestions: [String] = []

    // MARK: - Private

    private let service: MusicSearchService
    private var searchTask: Task<Void, Never>?

    private static let historyKey = "search_history"
    private static let maxHistory = 20

    // MARK: - Init

    init(service: MusicSearchService = iTunesService.shared) {
        self.service = service
        loadHistory()
    }

    // MARK: - Search

    func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            return
        }

        isSearching = true
        searchTask?.cancel()

        let tracks = await service.search(term: trimmed, limit: 50)
        results = tracks
        isSearching = false

        addToHistory(trimmed)
    }

    func searchDebounced() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    // MARK: - Suggestions

    func updateSuggestions() {
        let trimmed = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            suggestions = []
            return
        }
        suggestions = searchHistory.filter { $0.lowercased().contains(trimmed) }
    }

    // MARK: - History

    private func loadHistory() {
        searchHistory = UserDefaults.standard.stringArray(forKey: Self.historyKey) ?? []
    }

    private func addToHistory(_ term: String) {
        searchHistory.removeAll { $0.lowercased() == term.lowercased() }
        searchHistory.insert(term, at: 0)
        if searchHistory.count > Self.maxHistory {
            searchHistory = Array(searchHistory.prefix(Self.maxHistory))
        }
        UserDefaults.standard.set(searchHistory, forKey: Self.historyKey)
    }

    func removeFromHistory(_ term: String) {
        searchHistory.removeAll { $0 == term }
        UserDefaults.standard.set(searchHistory, forKey: Self.historyKey)
    }

    func clearHistory() {
        searchHistory.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.historyKey)
    }

    func clearResults() {
        results = []
        query = ""
    }
}
