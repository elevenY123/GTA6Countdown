import SwiftUI

struct CredibilityBadge: View {
    let credibility: Credibility

    var body: some View {
        Text(credibility.displayName)
            .font(AppTypography.metadata)
            .foregroundColor(foregroundColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(backgroundColor, in: Capsule())
            .accessibilityLabel("可信度：\(credibility.displayName)")
    }

    private var foregroundColor: Color {
        credibility == .official ? .white : AppColors.textPrimary
    }

    private var backgroundColor: Color {
        switch credibility {
        case .official: return AppColors.primary
        case .media: return AppColors.secondary.opacity(0.22)
        case .unverified: return Color.orange.opacity(0.24)
        }
    }
}
