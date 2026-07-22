import SwiftUI

enum ReleaseWaitingProgress {
    static func value(from confirmationDate: Date, to releaseDate: Date, at currentDate: Date) -> Double {
        let total = releaseDate.timeIntervalSince(confirmationDate)
        guard total > 0 else { return currentDate >= releaseDate ? 1 : 0 }
        return min(max(currentDate.timeIntervalSince(confirmationDate) / total, 0), 1)
    }
}

struct ReleaseProgressView: View {
    let confirmationDate: Date
    let releaseDate: Date
    let currentDate: Date

    private var progress: Double {
        ReleaseWaitingProgress.value(from: confirmationDate, to: releaseDate, at: currentDate)
    }

    private var percentage: Int {
        Int((progress * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppMetrics.compactSpacing) {
            HStack {
                Text("等待历程")
                    .font(AppTypography.headline)
                Spacer()
                Text("\(percentage)%")
                    .font(AppTypography.metadata)
                    .monospacedDigit()
            }

            ProgressView(value: progress)
                .tint(AppColors.primary)
                .accessibilityLabel("发售等待进度")
                .accessibilityValue(
                    "从首次确认开发到当前发售日期的等待时间，已走过百分之 \(percentage)"
                )

            Text("从首次确认开发到当前发售日期的时间进度，不代表游戏开发进度。")
                .font(AppTypography.metadata)
                .foregroundColor(AppColors.textSecondary)
        }
        .viceCardStyle()
    }
}
