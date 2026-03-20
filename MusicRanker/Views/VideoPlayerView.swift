import SwiftUI
import WebKit

/// In-app YouTube video player using WKWebView
struct VideoPlayerView: View {
    let title: String
    let artist: String
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var player: AudioPlayerManager

    private var searchURL: URL? {
        let query = "\(artist) \(title) official".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://m.youtube.com/results?search_query=\(query)")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let url = searchURL {
                    YouTubeWebView(url: url)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView(
                        "Vidéo indisponible",
                        systemImage: "play.slash",
                        description: Text("Impossible de chercher cette vidéo.")
                    )
                }
            }
            .navigationTitle("Vidéo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .onAppear {
            // Pause audio when watching video
            if player.isPlaying {
                player.togglePause()
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - WKWebView Wrapper

struct YouTubeWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            // Allow YouTube navigation only
            guard let url = navigationAction.request.url,
                  let host = url.host?.lowercased() else { return .allow }

            if host.contains("youtube.com") || host.contains("googlevideo.com") || host.contains("google.com") {
                return .allow
            }
            return .cancel
        }
    }
}
