import SwiftUI

struct NewsRow: View {
    let article: NewsArticle

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            NewsCoverImage(url: article.imageURL)
                .frame(width: 116, height: 92)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                CredibilityBadge(credibility: article.credibility)

                Text(article.title)
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                Text(metadata.displayText)
                    .font(AppTypography.metadata)
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(1)
                    .accessibilityLabel(metadata.accessibilityText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(AppColors.surface, in: RoundedRectangle(
            cornerRadius: AppMetrics.cardCornerRadius,
            style: .continuous
        ))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(article.credibility.displayName)，\(article.title)，\(metadata.accessibilityText)"
        )
        .accessibilityIdentifier("news-row-\(article.id)")
    }

    private var metadata: NewsMetadata { NewsMetadata(article: article) }
}

struct NewsMetadata: Equatable {
    let sourceName: String
    let publishedText: String

    init(article: NewsArticle) {
        sourceName = article.sourceName
        publishedText = article.publishedAt.newsRelativeText
    }

    var displayText: String { "\(sourceName) · \(publishedText)" }
    var accessibilityText: String { "来源：\(sourceName)，发布时间：\(publishedText)" }
}

extension Date {
    var newsRelativeText: String {
        formatted(
            .relative(presentation: .numeric, unitsStyle: .abbreviated)
                .locale(Locale(identifier: "zh_Hans_CN"))
        )
    }

    var newsAbsoluteText: String {
        formatted(
            .dateTime
                .year().month().day()
                .hour().minute()
                .locale(Locale(identifier: "zh_Hans_CN"))
        )
    }
}
