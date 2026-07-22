import SwiftUI
import UIKit

enum AppImageCache {
    static let shared: ImageCache? = {
        guard let directory = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        return try? ImageCache(
            directoryURL: directory,
            maximumDiskSize: 100 * 1_024 * 1_024
        )
    }()
}

struct AsyncCoverImage<Placeholder: View, Failure: View>: View {
    private enum Phase {
        case empty
        case success(UIImage)
        case failure
    }

    let url: URL?
    let cache: ImageCache?
    let contentMode: ContentMode
    let placeholder: () -> Placeholder
    let failure: () -> Failure

    @State private var phase: Phase = .empty

    init(
        url: URL?,
        cache: ImageCache? = AppImageCache.shared,
        contentMode: ContentMode = .fill,
        @ViewBuilder placeholder: @escaping () -> Placeholder,
        @ViewBuilder failure: @escaping () -> Failure
    ) {
        self.url = url
        self.cache = cache
        self.contentMode = contentMode
        self.placeholder = placeholder
        self.failure = failure
    }

    var body: some View {
        Group {
            switch phase {
            case .empty:
                placeholder()
                    .accessibilityLabel("封面加载中")
            case let .success(image):
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .accessibilityHidden(true)
            case .failure:
                failure()
                    .accessibilityLabel("封面暂不可用")
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        phase = .empty
        guard let url, let cache else {
            phase = .failure
            return
        }
        guard let data = await cache.data(for: url), !Task.isCancelled else {
            if !Task.isCancelled {
                phase = .failure
            }
            return
        }
        guard let image = UIImage(data: data) else {
            phase = .failure
            return
        }
        phase = .success(image)
    }
}

extension AsyncCoverImage where Placeholder == CoverImagePlaceholder, Failure == CoverImagePlaceholder {
    init(
        url: URL?,
        cache: ImageCache? = AppImageCache.shared,
        contentMode: ContentMode = .fill
    ) {
        self.init(
            url: url,
            cache: cache,
            contentMode: contentMode,
            placeholder: { CoverImagePlaceholder(systemImage: "photo") },
            failure: { CoverImagePlaceholder(systemImage: "exclamationmark.triangle") }
        )
    }
}

struct CoverImagePlaceholder: View {
    let systemImage: String

    var body: some View {
        ZStack {
            AppColors.surface
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundColor(AppColors.textSecondary)
        }
    }
}
