import SwiftUI

struct PinnedOfficialCard: View {
    let article: NewsArticle

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            NewsCoverImage(url: article.imageURL)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 300)
                .clipped()
                .accessibilityHidden(true)

            LinearGradient(
                colors: [.clear, .black.opacity(0.84)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 10) {
                CredibilityBadge(credibility: .official)
                Text(article.title)
                    .font(AppTypography.title)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                Text(metadata.displayText)
                    .font(AppTypography.metadata)
                    .foregroundColor(.white.opacity(0.82))
                    .accessibilityLabel(metadata.accessibilityText)
            }
            .padding(AppMetrics.standardSpacing)
        }
        .frame(minHeight: 300)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Rockstar 最新官方消息，\(article.title)，\(metadata.accessibilityText)"
        )
        .accessibilityIdentifier("news-pinned-official")
    }

    private var metadata: NewsMetadata { NewsMetadata(article: article) }
}
