import SwiftUI

struct CountdownHeroView: View {
    let state: CountdownState
    let message: String
    let releaseDate: Date

    @ScaledMetric(relativeTo: .largeTitle) private var dayNumberSize: CGFloat = 96

    var body: some View {
        VStack(spacing: AppMetrics.standardSpacing) {
            VStack(spacing: 2) {
                Text(state.isReleased ? "已发售" : "距离发售还有")
                    .font(AppTypography.headline)
                    .foregroundStyle(.white.opacity(0.9))

                if !state.isReleased {
                    Text(state.calendarDaysRemaining.formatted())
                        .font(.system(size: dayNumberSize, weight: .black, design: .rounded))
                        .minimumScaleFactor(0.55)
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .accessibilityLabel("剩余 \(state.calendarDaysRemaining) 天")

                    Text("天")
                        .font(AppTypography.title)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }

            if !state.isReleased {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: AppMetrics.compactSpacing) {
                        timePart(state.preciseDays, label: "天")
                        timePart(state.hours, label: "时")
                        timePart(state.minutes, label: "分")
                        timePart(state.seconds, label: "秒")
                    }
                    .fixedSize(horizontal: true, vertical: false)

                    VStack(spacing: AppMetrics.compactSpacing) {
                        HStack(spacing: AppMetrics.compactSpacing) {
                            timePart(state.preciseDays, label: "天")
                            timePart(state.hours, label: "时")
                        }
                        HStack(spacing: AppMetrics.compactSpacing) {
                            timePart(state.minutes, label: "分")
                            timePart(state.seconds, label: "秒")
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "精确倒计时，\(state.preciseDays) 天 \(state.hours) 小时 \(state.minutes) 分 \(state.seconds) 秒"
                )
            }

            Text(message)
                .font(AppTypography.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)

            Text("正式发售日期 · \(releaseDate.formatted(.dateTime.year().month().day()))")
                .font(AppTypography.metadata)
                .foregroundStyle(.white.opacity(0.82))
        }
        .padding(.horizontal, AppMetrics.standardSpacing)
        .padding(.vertical, 28)
    }

    private func timePart(_ value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text(String(format: "%02d", value))
                .font(.system(.title2, design: .rounded).weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(AppTypography.metadata)
        }
        .frame(minWidth: 58, maxWidth: .infinity)
        .padding(.vertical, AppMetrics.compactSpacing)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
