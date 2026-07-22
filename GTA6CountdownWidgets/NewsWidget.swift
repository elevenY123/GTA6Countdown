import SwiftUI
import UIKit
import WidgetKit

struct NewsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.news, provider: NewsTimelineProvider()) { entry in
            NewsWidgetView(entry: entry)
        }
        .configurationDisplayName("GTA VI 中文资讯")
        .description("快速查看最新 GTA VI 中文消息。")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

private struct NewsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.sizeCategory) private var sizeCategory
    let entry: NewsWidgetEntry

    var body: some View {
        ZStack {
            ViceWidgetBackground()
            content
                .padding(14)
        }
        .widgetURL(defaultDeepLink)
    }

    @ViewBuilder
    private var content: some View {
        switch entry.status {
        case let .available(display, isCached):
            if family == .systemLarge {
                largeContent(display: display, isCached: isCached)
            } else {
                mediumContent(display: display, isCached: isCached)
            }
        case .empty:
            WidgetEmptyState(
                title: "暂时没有新消息",
                detail: "稍后再来看看，罪恶城还在准备。",
                systemImage: "newspaper"
            )
        case .unavailable:
            WidgetEmptyState(
                title: "资讯暂不可用",
                detail: "连接恢复后会自动更新。",
                systemImage: "wifi.exclamationmark"
            )
        }
    }

    private func mediumContent(display: WidgetNewsDisplay, isCached: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            header(isCached: isCached)
            ForEach(Array(display.selection.medium.prefix(layoutPolicy.newsRowLimit))) { article in
                WidgetNewsRow(
                    article: article,
                    coverData: display.coverDataByArticleID[article.id],
                    compact: true,
                    showsMetadata: layoutPolicy.showsNewsMetadata
                )
            }
            if display.selection.medium.isEmpty {
                Spacer()
                Text("暂时没有新消息")
                    .foregroundColor(.white.opacity(0.82))
                Spacer()
            }
        }
    }

    private func largeContent(display: WidgetNewsDisplay, isCached: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(isCached: isCached)
            if let lead = display.selection.largeLead {
                WidgetLeadStory(
                    article: lead,
                    coverData: display.coverDataByArticleID[lead.id],
                    isAccessibilitySize: sizeCategory.isAccessibilityCategory
                )
            }
            ForEach(Array(display.selection.largeRows.prefix(layoutPolicy.newsRowLimit))) { article in
                WidgetNewsRow(
                    article: article,
                    coverData: display.coverDataByArticleID[article.id],
                    compact: false,
                    showsMetadata: layoutPolicy.showsNewsMetadata
                )
            }
            Spacer(minLength: 0)
        }
    }

    private func header(isCached: Bool) -> some View {
        HStack {
            Text("GTA VI 资讯")
                .font(.headline.weight(.black))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Spacer()
            if isCached {
                Text("缓存")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.white.opacity(0.72))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var defaultDeepLink: URL? {
        guard case let .available(display, _) = entry.status else {
            return WidgetNewsRoute.newsURL
        }
        return display.selection.medium.first.flatMap { WidgetNewsRoute.articleURL(id: $0.id) }
            ?? display.selection.largeLead.flatMap { WidgetNewsRoute.articleURL(id: $0.id) }
    }

    private var layoutPolicy: WidgetLayoutPolicy {
        WidgetLayoutPolicy.make(
            family: family == .systemLarge ? .large : .medium,
            isAccessibilitySize: sizeCategory.isAccessibilityCategory
        )
    }
}

private struct WidgetLeadStory: View {
    let article: NewsArticle
    let coverData: Data?
    let isAccessibilitySize: Bool

    var body: some View {
        Link(destination: WidgetNewsRoute.articleURL(id: article.id) ?? WidgetNewsRoute.newsURL) {
            ZStack(alignment: .bottomLeading) {
                WidgetCover(data: coverData)
                LinearGradient(colors: [.clear, .black.opacity(0.82)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 3) {
                    Text(article.isOfficial ? "ROCKSTAR 官方" : article.sourceName)
                        .font(.caption2.weight(.black))
                        .foregroundColor(.pink.opacity(0.95))
                    Text(article.title)
                        .font((isAccessibilitySize ? Font.caption : Font.subheadline).weight(.bold))
                        .foregroundColor(.white)
                        .lineLimit(isAccessibilitySize ? 1 : 2)
                        .minimumScaleFactor(0.75)
                }
                .padding(10)
            }
            .frame(height: isAccessibilitySize ? 82 : 112)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .accessibilityLabel("\(article.isOfficial ? "官方消息" : "资讯")，\(article.title)，来源 \(article.sourceName)")
        .accessibilityHint("打开新闻详情")
    }
}

private struct WidgetNewsRow: View {
    let article: NewsArticle
    let coverData: Data?
    let compact: Bool
    let showsMetadata: Bool

    var body: some View {
        Link(destination: WidgetNewsRoute.articleURL(id: article.id) ?? WidgetNewsRoute.newsURL) {
            HStack(spacing: 9) {
                WidgetCover(data: coverData)
                    .frame(width: compact ? 58 : 48, height: compact ? 48 : 40)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(article.title)
                        .font(compact ? .caption.weight(.bold) : .caption.weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                    if showsMetadata {
                        Text(article.isOfficial ? "官方 · \(article.sourceName)" : article.sourceName)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.68))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityLabel("\(article.title)，来源 \(article.sourceName)\(article.isOfficial ? "，官方消息" : "")")
        .accessibilityHint("打开新闻详情")
    }
}

private struct WidgetCover: View {
    let data: Data?

    var body: some View {
        Group {
            if let data, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [Color.pink.opacity(0.95), Color.purple.opacity(0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Text("VI")
                        .font(.title2.weight(.black))
                        .foregroundColor(.white.opacity(0.88))
                }
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

private struct WidgetEmptyState: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2.weight(.bold))
            Text(title).font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.75))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
