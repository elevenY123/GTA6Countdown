import SwiftUI

enum RootTab: String, CaseIterable {
    case home
    case news
    case map

    var title: String {
        switch self {
        case .home: return "主页"
        case .news: return "新闻"
        case .map: return "地图"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "calendar"
        case .news: return "newspaper"
        case .map: return "map"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .home: return "root-tab-home"
        case .news: return "root-tab-news"
        case .map: return "root-tab-map"
        }
    }
}

struct RootTabView: View {
    @State private var selection = RootTab.home
    @State private var deepLinkedNewsArticleID: String?

    var body: some View {
        TabView(selection: $selection) {
            ForEach(RootTab.allCases, id: \.self) { tab in
                NavigationView {
                    root(for: tab)
                }
                .navigationViewStyle(.stack)
                .tabItem {
                    Label(tab.title, systemImage: tab.systemImage)
                        .accessibilityLabel(tab.title)
                        .accessibilityIdentifier(tab.accessibilityIdentifier)
                }
                .tag(tab)
                .accessibilityIdentifier(tab.accessibilityIdentifier)
            }
        }
        .accentColor(AppColors.primary)
        .onOpenURL { url in
            if case let .article(id)? = NewsRoute(url: url) {
                deepLinkedNewsArticleID = id
                selection = .news
            } else if url.scheme?.lowercased() == "gta6countdown" {
                switch url.host?.lowercased() {
                case "home": selection = .home
                case "news": selection = .news
                default: break
                }
            }
        }
    }

    @ViewBuilder
    private func root(for tab: RootTab) -> some View {
        switch tab {
        case .home:
            HomeView()
        case .news:
            NewsListView(deepLinkedArticleID: $deepLinkedNewsArticleID)
        case .map:
            MapView()
        }
    }
}
