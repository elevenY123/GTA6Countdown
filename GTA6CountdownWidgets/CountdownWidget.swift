import SwiftUI
import WidgetKit

struct CountdownWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.countdown, provider: CountdownTimelineProvider()) { entry in
            CountdownWidgetView(entry: entry)
        }
        .configurationDisplayName("GTA VI 发售倒计时")
        .description("查看距离 GTA VI 发售还有多少天。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct CountdownWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.sizeCategory) private var sizeCategory
    let entry: CountdownWidgetEntry

    var body: some View {
        ZStack {
            ViceWidgetBackground()
            HStack(spacing: 16) {
                countdown
                if family == .systemMedium {
                    Divider().overlay(Color.white.opacity(0.22))
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.content.message)
                            .font(sizeCategory.isAccessibilityCategory ? .caption.weight(.bold) : .headline)
                            .foregroundColor(.white)
                            .lineLimit(sizeCategory.isAccessibilityCategory ? 2 : 3)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: 0)
                        if layoutPolicy.showsCountdownMessage {
                            Text(entry.content.releaseDate, format: .dateTime.year().month().day())
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.white.opacity(0.76))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
        .widgetURL(WidgetNewsRoute.homeURL)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var countdown: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("GTA VI")
                .font(.caption.weight(.heavy))
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            Text(entry.content.isReleased ? "今天" : "\(entry.content.daysRemaining)")
                .font(.system(size: countdownFontSize, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundColor(.white)
            Text(entry.content.isReleased ? "正式发售" : "天后发售")
                .font(.subheadline.weight(.bold))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            if family == .systemSmall, layoutPolicy.showsCountdownMessage {
                Text(entry.content.message)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.white.opacity(0.76))
                    .lineLimit(2)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: family == .systemSmall ? .infinity : 116, alignment: .leading)
    }

    private var accessibilityLabel: String {
        if entry.content.isReleased {
            return "GTA VI 今天发售。\(entry.content.message)"
        }
        return "距离 GTA VI 发售还有 \(entry.content.daysRemaining) 天。\(entry.content.message)"
    }

    private var countdownFontSize: CGFloat {
        if sizeCategory.isAccessibilityCategory { return family == .systemSmall ? 34 : 40 }
        return family == .systemSmall ? 48 : 54
    }

    private var layoutPolicy: WidgetLayoutPolicy {
        WidgetLayoutPolicy.make(
            family: family == .systemSmall ? .small : .medium,
            isAccessibilitySize: sizeCategory.isAccessibilityCategory
        )
    }
}

struct ViceWidgetBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(red: 0.10, green: 0.03, blue: 0.19), Color(red: 0.48, green: 0.05, blue: 0.35)]
                : [Color(red: 0.94, green: 0.22, blue: 0.46), Color(red: 0.97, green: 0.47, blue: 0.25)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color.orange.opacity(colorScheme == .dark ? 0.20 : 0.34))
                .frame(width: 150, height: 150)
                .offset(x: 46, y: -70)
        }
    }
}
