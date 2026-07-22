import SwiftUI

enum AppMetrics {
    static let minimumTapTarget: CGFloat = 44
    static let cardCornerRadius: CGFloat = 18
    static let compactSpacing: CGFloat = 8
    static let standardSpacing: CGFloat = 16
}

struct ViceCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(AppMetrics.standardSpacing)
            .background(.regularMaterial, in: RoundedRectangle(
                cornerRadius: AppMetrics.cardCornerRadius,
                style: .continuous
            ))
    }
}

struct MinimumTapTarget: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(
                minWidth: AppMetrics.minimumTapTarget,
                minHeight: AppMetrics.minimumTapTarget
            )
            .contentShape(Rectangle())
    }
}

extension View {
    func viceCardStyle() -> some View {
        modifier(ViceCardStyle())
    }

    func minimumTapTarget() -> some View {
        modifier(MinimumTapTarget())
    }
}
