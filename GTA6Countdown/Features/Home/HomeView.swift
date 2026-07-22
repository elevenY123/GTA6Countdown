import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel: HomeViewModel
    @State private var isShowingAbout = false

    @MainActor
    init() {
        _viewModel = StateObject(wrappedValue: HomeViewModel())
    }

    @MainActor
    init(viewModel: @autoclosure @escaping () -> HomeViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: AppMetrics.standardSpacing) {
                    hero

                    ReleaseProgressView(
                        confirmationDate: viewModel.firstConfirmationDate,
                        releaseDate: viewModel.releaseDate,
                        currentDate: viewModel.currentDate
                    )
                    .padding(.horizontal, AppMetrics.standardSpacing)
                }
                .padding(.bottom, AppMetrics.standardSpacing)
            }
        }
        .navigationTitle("GTA VI 倒计时")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isShowingAbout = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .minimumTapTarget()
                .accessibilityLabel("关于与说明")
                .accessibilityIdentifier("home-about-button")
            }
        }
        .sheet(isPresented: $isShowingAbout) {
            AboutView()
        }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
        .accessibilityIdentifier("root-screen-home")
    }

    private var hero: some View {
        ZStack {
            artworkOrPlaceholder

            LinearGradient(
                colors: [.black.opacity(0.34), .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )

            CountdownHeroView(
                state: viewModel.countdown,
                message: viewModel.milestoneMessage,
                releaseDate: viewModel.releaseDate
            )
        }
        .clipped()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var artworkOrPlaceholder: some View {
        let assetName = colorScheme == .dark ? "HeroDark" : "HeroLight"
        if let artwork = UIImage(named: assetName) {
            Image(uiImage: artwork)
                .resizable()
                .scaledToFill()
                .accessibilityHidden(true)
        } else {
            LinearGradient(
                colors: [AppColors.accent, AppColors.secondary, AppColors.primary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}
