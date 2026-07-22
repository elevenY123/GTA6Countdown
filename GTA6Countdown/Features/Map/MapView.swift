import SwiftUI

struct MapView: View {
    @StateObject private var viewModel: MapViewModel

    @MainActor
    init() {
        _viewModel = StateObject(wrappedValue: MapViewModel())
    }

    @MainActor
    init(viewModel: @autoclosure @escaping () -> MapViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        VStack(spacing: 0) {
            communityNotice
            mapContent
            mapControls
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("社区预测地图")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("root-screen-map")
    }

    private var communityNotice: some View {
        VStack(alignment: .leading, spacing: AppMetrics.compactSpacing) {
            Label("社区预测地图", systemImage: "person.3.fill")
                .font(AppTypography.headline)
                .foregroundColor(AppColors.textPrimary)

            Text("该地图由玩家依据公开资料推测绘制，并非 Rockstar 官方最终地图。")
                .font(AppTypography.body)
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("地图与数据来自 MyGTA 中文社区")
                .font(AppTypography.metadata)
                .foregroundColor(AppColors.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppMetrics.standardSpacing)
        .padding(.vertical, AppMetrics.compactSpacing)
        .background(.regularMaterial)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("map-community-notice")
    }

    private var mapContent: some View {
        ZStack {
            MapWebView(viewModel: viewModel)
                .accessibilityIdentifier("map-web-view")
                .allowsHitTesting(viewModel.errorMessage == nil)
                .accessibilityHidden(viewModel.errorMessage != nil)

            if viewModel.isLoading && viewModel.errorMessage == nil {
                ProgressView("正在加载社区地图…")
                    .padding(AppMetrics.standardSpacing)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityIdentifier("map-loading")
            }

            if let errorMessage = viewModel.errorMessage {
                VStack(spacing: AppMetrics.standardSpacing) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 38))
                        .foregroundColor(AppColors.textSecondary)
                    Text(errorMessage)
                        .font(AppTypography.body)
                        .multilineTextAlignment(.center)
                    Button("重新加载") { viewModel.retry() }
                        .buttonStyle(.borderedProminent)
                        .tint(AppColors.primary)
                        .minimumTapTarget()
                }
                .padding(AppMetrics.standardSpacing)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius))
                .padding(AppMetrics.standardSpacing)
                .accessibilityIdentifier("map-error")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mapControls: some View {
        HStack(spacing: AppMetrics.compactSpacing) {
            mapButton("后退", systemImage: "chevron.backward", enabled: viewModel.canGoBack) {
                viewModel.goBack()
            }
            mapButton("前进", systemImage: "chevron.forward", enabled: viewModel.canGoForward) {
                viewModel.goForward()
            }
            mapButton("刷新", systemImage: "arrow.clockwise") {
                viewModel.refresh()
            }

            Spacer(minLength: AppMetrics.compactSpacing)

            Button {
                viewModel.openInSafari()
            } label: {
                Label("打开 Safari", systemImage: "safari")
                    .font(.body.weight(.semibold))
            }
            .minimumTapTarget()
            .accessibilityHint("使用系统浏览器打开 MyGTA 社区地图")
            .accessibilityIdentifier("map-open-safari")
        }
        .padding(.horizontal, AppMetrics.standardSpacing)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func mapButton(
        _ title: String,
        systemImage: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 28, height: 28)
        }
        .minimumTapTarget()
        .disabled(!enabled)
        .accessibilityLabel(title)
        .accessibilityIdentifier("map-\(title)")
    }
}
