import SwiftUI

struct NewsListView: View {
    @StateObject private var viewModel: NewsViewModel
    @Binding private var deepLinkedArticleID: String?

    init(
        viewModel: @autoclosure @escaping () -> NewsViewModel = NewsViewModel(),
        deepLinkedArticleID: Binding<String?> = .constant(nil)
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        _deepLinkedArticleID = deepLinkedArticleID
    }

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            stateContent
            deepLinkNavigation
        }
        .navigationTitle("新闻")
        .task { await viewModel.load() }
        .accessibilityIdentifier("root-screen-news")
    }

    @ViewBuilder
    private var deepLinkNavigation: some View {
        if let id = deepLinkedArticleID, let article = viewModel.article(id: id) {
            NavigationLink(
                destination: NewsDetailView(article: article),
                isActive: Binding(
                    get: { deepLinkedArticleID == article.id },
                    set: { if !$0 { deepLinkedArticleID = nil } }
                ),
                label: { EmptyView() }
            )
            .hidden()
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        if viewModel.isInitialLoading {
            ProgressView("正在获取 GTA VI 最新消息…")
                .accessibilityIdentifier("news-loading")
        } else if viewModel.isUnavailable {
            NewsStateMessage(
                systemImage: "wifi.exclamationmark",
                title: "暂时无法获取新闻",
                message: "请检查网络后重试。",
                actionTitle: "重新加载",
                action: { Task { await viewModel.refresh() } }
            )
            .accessibilityIdentifier("news-unavailable")
        } else if viewModel.isEmpty {
            NewsStateMessage(
                systemImage: "newspaper",
                title: "暂无 GTA VI 新闻",
                message: "下拉刷新，稍后再来看看。",
                actionTitle: "刷新",
                action: { Task { await viewModel.refresh() } }
            )
            .accessibilityIdentifier("news-empty")
        } else {
            newsContent
        }
    }

    private var newsContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppMetrics.standardSpacing) {
                if let issue = viewModel.issue {
                    offlineBanner(issue: issue)
                }

                if let pinned = viewModel.presentation.pinnedOfficial {
                    NavigationLink(destination: NewsDetailView(article: pinned)) {
                        PinnedOfficialCard(article: pinned)
                    }
                    .buttonStyle(.plain)
                }

                if !viewModel.presentation.articles.isEmpty {
                    Text("最新资讯")
                        .font(AppTypography.title)
                        .foregroundColor(AppColors.textPrimary)

                    ForEach(viewModel.presentation.articles) { article in
                        NavigationLink(destination: NewsDetailView(article: article)) {
                            NewsRow(article: article)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let updatedAt = viewModel.payload?.updatedAt {
                    Text("上次更新：\(updatedAt.newsAbsoluteText)")
                        .font(AppTypography.metadata)
                        .foregroundColor(AppColors.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(AppMetrics.standardSpacing)
        }
        .refreshable { await viewModel.refresh() }
        .accessibilityIdentifier("news-content")
    }

    private func offlineBanner(issue: NewsRepositoryIssue) -> some View {
        Label(
            viewModel.source == .cache ? "网络暂不可用，正在显示上次缓存的内容" : "内容已更新，但本地缓存暂不可用",
            systemImage: viewModel.source == .cache ? "wifi.slash" : "exclamationmark.triangle"
        )
        .font(.footnote)
        .foregroundColor(AppColors.textSecondary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("news-nonblocking-error")
    }
}

private struct NewsStateMessage: View {
    let systemImage: String
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: AppMetrics.standardSpacing) {
            Image(systemName: systemImage)
                .font(.system(size: 42))
                .foregroundColor(AppColors.textSecondary)
            Text(title)
                .font(AppTypography.title)
                .multilineTextAlignment(.center)
            Text(message)
                .font(AppTypography.body)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
                .tint(AppColors.primary)
                .minimumTapTarget()
        }
        .padding(AppMetrics.standardSpacing)
    }
}
