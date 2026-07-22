import SwiftUI
import UIKit

struct NewsCoverImage: View {
    let url: URL?

    var body: some View {
        AsyncCoverImage(
            url: url,
            placeholder: { NewsCoverPlaceholder(isFailure: false) },
            failure: { NewsCoverPlaceholder(isFailure: true) }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("GTA VI 新闻封面")
    }
}

struct NewsCoverPlaceholder: View {
    let isFailure: Bool

    var body: some View {
        ZStack {
            if let placeholder = UIImage(named: "NewsPlaceholder") {
                Image(uiImage: placeholder)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [AppColors.accent, AppColors.primary, AppColors.secondary],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            if isFailure {
                Image(systemName: "newspaper.fill")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(.black.opacity(0.45), in: Circle())
            }
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isFailure ? "GTA VI 新闻封面占位图" : "GTA VI 新闻封面加载中")
    }
}
