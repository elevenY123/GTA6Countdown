import SafariServices
import SwiftUI

struct NewsDetailView: View {
    let article: NewsArticle
    let originalLinkAction: NewsOriginalLinkAction?
    @State private var safariDestination: SafariDestination?

    init(article: NewsArticle, originalLinkAction: NewsOriginalLinkAction? = nil) {
        self.article = article
        self.originalLinkAction = originalLinkAction
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppMetrics.standardSpacing) {
                NewsCoverImage(url: article.imageURL)
                    .frame(maxWidth: .infinity)
                    .frame(height: 230)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius))
                    .accessibilityHidden(true)

                CredibilityBadge(credibility: article.credibility)
                Text(article.title)
                    .font(AppTypography.title)
                    .foregroundColor(AppColors.textPrimary)

                Text("\(article.sourceName) · \(article.publishedAt.newsAbsoluteText)")
                    .font(AppTypography.metadata)
                    .foregroundColor(AppColors.textSecondary)

                Text(article.summary)
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("news-detail-summary")

                Label(article.credibility.explanation, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    if let originalLinkAction {
                        originalLinkAction.open(article.sourceURL)
                    } else {
                        safariDestination = SafariDestination(url: article.sourceURL)
                    }
                } label: {
                    Label("阅读原文", systemImage: "safari")
                        .font(AppTypography.headline)
                        .frame(maxWidth: .infinity)
                        .minimumTapTarget()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.primary)
                .accessibilityHint("打开 \(article.sourceName) 的原始网页")
                .accessibilityIdentifier("news-read-original")
            }
            .padding(AppMetrics.standardSpacing)
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("新闻详情")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("news-detail-\(article.id)")
        .sheet(item: $safariDestination) { destination in
            SafariView(url: destination.url)
                .ignoresSafeArea()
        }
    }
}

struct NewsOriginalLinkAction {
    private let handler: (URL) -> Void

    init(handler: @escaping (URL) -> Void) { self.handler = handler }

    func open(_ url: URL) { handler(url) }
}

struct NewsDetailContent: Equatable {
    let summary: String
    let originalURL: URL
    let originalButtonTitle = "阅读原文"

    init(article: NewsArticle) {
        summary = article.summary
        originalURL = article.sourceURL
    }
}

private struct SafariDestination: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
