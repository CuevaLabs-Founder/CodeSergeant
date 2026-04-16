//
//  MenuBarView.swift
//  CodeSergeantUI
//
//  Single-window menu bar container with a shared fixed size.
//

import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    @State private var hostedWindow: NSWindow?
    @State private var anchorMidX: CGFloat?
    @State private var anchorTopY: CGFloat?

    var body: some View {
        ZStack {
            GlassBackground()

            Group {
                switch appState.menuPanel {
                case .home:
                    HomePanel()
                case .session:
                    DashboardView()
                case .settings:
                    SettingsPanelContainer()
                }
            }
            .padding(AppTheme.shellInset)
        }
        .frame(width: panelSize.width, height: panelSize.height)
        .clipShape(.rect(cornerRadius: 18))
        .warningStrobe(status: appState.warningStatus)
        .background {
            MenuBarWindowAccessor { window in
                captureWindow(window)
            }
        }
        .onAppear {
            repositionWindow()
        }
        .onChange(of: appState.menuPanel) {
            repositionWindow()
        }
        .onChange(of: appState.isSessionActive) {
            repositionWindow()
        }
    }

    private var panelSize: CGSize {
        CGSize(width: AppTheme.panelWidth, height: AppTheme.panelHeight)
    }

    private func captureWindow(_ window: NSWindow?) {
        guard let window else { return }

        if hostedWindow !== window {
            hostedWindow = window
            anchorMidX = window.frame.midX
            anchorTopY = window.frame.maxY
            repositionWindow()
        }
    }

    private func repositionWindow() {
        DispatchQueue.main.async {
            guard let window = hostedWindow else { return }

            if anchorMidX == nil {
                anchorMidX = window.frame.midX
            }
            if anchorTopY == nil {
                anchorTopY = window.frame.maxY
            }

            let targetSize = panelSize
            var frame = window.frame
            let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? frame

            frame.size = targetSize
            frame.origin.x = (anchorMidX ?? window.frame.midX) - (targetSize.width / 2)
            frame.origin.y = (anchorTopY ?? window.frame.maxY) - targetSize.height

            let horizontalInset: CGFloat = 12
            let verticalInset: CGFloat = 8
            let minX = visibleFrame.minX + horizontalInset
            let maxX = visibleFrame.maxX - targetSize.width - horizontalInset
            let minY = visibleFrame.minY + verticalInset
            let maxY = visibleFrame.maxY - targetSize.height

            frame.origin.x = min(max(frame.origin.x, minX), maxX)
            frame.origin.y = min(max(frame.origin.y, minY), maxY)

            window.setFrame(frame, display: true, animate: false)
        }
    }
}

private struct HomePanel: View {
    @EnvironmentObject var appState: AppState
    @State private var showingEndSessionConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuBarHeader(
                isSessionActive: appState.isSessionActive,
                currentRank: appState.currentRank
            )
            .padding(AppTheme.chromePadding)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                if appState.isSessionActive {
                    HStack(alignment: .top, spacing: 12) {
                        XPDisplay(
                            totalXP: appState.totalXP,
                            sessionXP: appState.sessionXP,
                            currentRank: appState.currentRank,
                            rankProgress: appState.rankProgress,
                            nextRankName: appState.nextRankName,
                            xpToNextRank: appState.xpToNextRank,
                            isCompact: true
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)

                        CompactTimerDisplay(
                            remainingSeconds: appState.remainingSeconds,
                            isBreak: appState.isBreak
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !appState.sessionGoal.isEmpty {
                        HoverGlassCard(cornerRadius: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Current mission", systemImage: "target")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Text(appState.sessionGoal)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(2)
                            }
                            .padding(14)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No Active Session",
                        systemImage: "moon.zzz.fill",
                        description: Text("Start a focus session to track time, XP, and warnings.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
            .padding(AppTheme.chromePadding)

            Divider()

            VStack(spacing: 8) {
                if appState.isSessionActive {
                    HStack(spacing: 8) {
                        MenuBarButton(
                            title: "Session View",
                            icon: "rectangle.portrait.on.rectangle.portrait.fill",
                            tint: AppTheme.primaryTint
                        ) {
                            appState.showSession()
                        }

                        MenuBarButton(
                            title: appState.isPaused ? "Resume" : "Pause",
                            icon: appState.isPaused ? "play.fill" : "pause.fill",
                            tint: AppTheme.primaryTint,
                            action: pauseOrResume
                        )
                    }

                    HStack(spacing: 8) {
                        if appState.isBreak {
                            MenuBarButton(
                                title: "Skip Break",
                                icon: "forward.fill",
                                tint: AppTheme.successTint,
                                action: appState.skipBreak
                            )
                        }

                        MenuBarButton(
                            title: "Settings",
                            icon: "gearshape.fill",
                            tint: AppTheme.canvasAccent
                        ) {
                            appState.showSettings()
                        }

                        if !appState.isBreak {
                            MenuBarButton(
                                title: "Quit Session",
                                icon: "stop.fill",
                                tint: AppTheme.dangerTint
                            ) {
                                showingEndSessionConfirmation = true
                            }
                        }
                    }

                    if appState.isBreak {
                        MenuBarButton(
                            title: "Quit Session",
                            icon: "stop.fill",
                            tint: AppTheme.dangerTint
                        ) {
                            showingEndSessionConfirmation = true
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        MenuBarButton(
                            title: "Start Focus Session",
                            icon: "play.fill",
                            tint: AppTheme.primaryTint
                        ) {
                            appState.showSession()
                        }

                        MenuBarButton(
                            title: "Settings",
                            icon: "gearshape.fill",
                            tint: AppTheme.canvasAccent
                        ) {
                            appState.showSettings()
                        }
                    }
                }

                MenuBarButton(
                    title: "Quit App",
                    icon: "power",
                    tint: AppTheme.warningTint
                ) {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(AppTheme.chromePadding)
        }
        .background(.thinMaterial)
        .confirmationDialog(
            "Quit session early?",
            isPresented: $showingEndSessionConfirmation,
            titleVisibility: .visible
        ) {
            Button("Quit Session", role: .destructive) {
                appState.endSession(early: true)
            }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text("Ending now applies your configured early-exit XP penalty.")
        }
    }

    private func pauseOrResume() {
        if appState.isPaused {
            appState.resumeSession()
        } else {
            appState.pauseSession()
        }
    }
}

private struct SettingsPanelContainer: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                LiquidIconButton("Back", icon: "chevron.left") {
                    appState.closeSettings()
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Settings")
                        .font(.headline)
                    Text("Everything stays in the menu bar now.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, AppTheme.chromePadding)
            .padding(.top, AppTheme.chromePadding)
            .padding(.bottom, 8)

            SettingsView()
                .environmentObject(appState)
        }
    }
}

private struct MenuBarHeader: View {
    let isSessionActive: Bool
    let currentRank: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.title2.weight(.bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppTheme.canvasAccent, AppTheme.primaryTint],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Code Sergeant")
                    .font(.headline)

                Text(isSessionActive ? "Active • \(currentRank)" : "Ready • \(currentRank)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

private struct MenuBarButton: View {
    let title: String
    let icon: String
    let tint: Color
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: AppTheme.controlMinHeight)
            .padding(.horizontal, 14)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(isHovering ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(tint.opacity(0.18), lineWidth: 1)
                    }
            }
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(tint)
                    .frame(width: 3)
                    .padding(.vertical, 10)
                    .clipShape(.rect(cornerRadius: 3))
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .help(title)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

private struct MenuBarWindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            onResolve(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            onResolve(nsView.window)
        }
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AppState())
}
