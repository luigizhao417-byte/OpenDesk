import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    @State private var draftText = ""
    @State private var isTaskCenterPresented = false
    @State private var isAgentCenterPresented = false

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                SidebarView()

                Rectangle()
                    .fill(AppTheme.subtleBorder)
                    .frame(width: 1)

                ChatDetailView(
                    draftText: $draftText,
                    isTaskCenterPresented: $isTaskCenterPresented,
                    isAgentCenterPresented: $isAgentCenterPresented
                )
            }
            .background(AppTheme.canvas)

            if appState.isOnboardingPresented {
                onboardingOverlay
            }
        }
        .sheet(isPresented: $isTaskCenterPresented) {
            TaskCenterView(prefillText: $draftText)
                .environmentObject(appState)
                .frame(minWidth: 760, minHeight: 660)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $isAgentCenterPresented) {
            AgentCenterView(prefillGoal: $draftText)
                .environmentObject(appState)
                .frame(minWidth: 920, minHeight: 760)
                .preferredColorScheme(.dark)
        }
    }

    private var onboardingOverlay: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.7))
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(appState.text("onboarding.badge"))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(AppTheme.accent.opacity(0.9))
                            )

                        Text(appState.text("onboarding.title"))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text(appState.text("onboarding.subtitle"))
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    if appState.hasCompletedOnboarding {
                        Button {
                            appState.dismissOnboarding()
                        } label: {
                            Label(appState.text("onboarding.close"), systemImage: "xmark")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .foregroundStyle(.white)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.white.opacity(0.06))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text(appState.text("onboarding.language.title"))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(appState.text("onboarding.language.subtitle"))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)

                    Picker("", selection: Binding(
                        get: { appState.appLanguage },
                        set: { appState.setLanguage($0) }
                    )) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(spacing: 14) {
                    OnboardingFeatureCard(
                        title: appState.text("onboarding.step1.title"),
                        detail: appState.text("onboarding.step1.body")
                    )
                    OnboardingFeatureCard(
                        title: appState.text("onboarding.step2.title"),
                        detail: appState.text("onboarding.step2.body")
                    )
                    OnboardingFeatureCard(
                        title: appState.text("onboarding.step3.title"),
                        detail: appState.text("onboarding.step3.body")
                    )
                    OnboardingFeatureCard(
                        title: appState.text("onboarding.step4.title"),
                        detail: appState.text("onboarding.step4.body")
                    )
                }

                Text(appState.text("onboarding.tip"))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer()

                    Button {
                        appState.completeOnboarding()
                    } label: {
                        Label(appState.text("onboarding.start"), systemImage: "arrow.right.circle.fill")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 13)
                            .foregroundStyle(.white)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(AppTheme.accent)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(28)
            .frame(maxWidth: 780)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(AppTheme.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(AppTheme.border, lineWidth: 1)
                    )
            )
            .padding(28)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }
}

private struct OnboardingFeatureCard: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(detail)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.panelSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
        )
    }
}
