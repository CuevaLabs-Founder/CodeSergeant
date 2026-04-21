//
//  DashboardView.swift
//  CodeSergeantUI
//
//  Main dashboard with a compact horizontal session layout for the menu bar app.
//

import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var animateIn = false
    @State private var showingEndSessionConfirmation = false

    var body: some View {
        ZStack {
            VStack(spacing: layoutSpacing) {
                DashboardHeader(
                    isSessionActive: appState.isSessionActive,
                    isCompact: appState.isSessionActive,
                    showHome: appState.showHome,
                    showSettings: appState.showSettings
                )
                .offset(y: animateIn ? 0 : -16)
                .opacity(animateIn ? 1 : 0)

                Group {
                    if appState.isSessionActive {
                        ActiveSessionPanel(
                            goal: appState.sessionGoal,
                            remainingSeconds: appState.remainingSeconds,
                            totalSeconds: max(Int(appState.workMinutes) * 60, appState.remainingSeconds),
                            isBreak: appState.isBreak,
                            pomodoroState: appState.pomodoroState,
                            sessionEndedEarly: appState.sessionEndedEarly,
                            totalXP: appState.totalXP,
                            sessionXP: appState.sessionXP,
                            currentRank: appState.currentRank,
                            rankProgress: appState.rankProgress,
                            nextRankName: appState.nextRankName,
                            xpToNextRank: appState.xpToNextRank,
                            focusTimeMinutes: appState.focusTimeMinutes,
                            isPaused: appState.isPaused,
                            pauseAction: pauseOrResume,
                            endAction: { showingEndSessionConfirmation = true },
                            skipAction: appState.isBreak ? { appState.skipBreak() } : nil
                        )
                    } else {
                        StartSessionPanel(
                            goalText: $appState.draftGoal,
                            workMinutes: $appState.workMinutes,
                            breakMinutes: $appState.breakMinutes,
                            isStartingSession: appState.isStartingSession,
                            errorMessage: appState.sessionErrorMessage,
                            startAction: startSession
                        )
                    }
                }
                .transition(contentTransition)

                DashboardFooter(
                    backendName: backendName,
                    screenMonitoringEnabled: appState.screenMonitoringEnabled,
                    lastJudgmentText: appState.lastJudgmentText,
                    warningStatus: appState.warningStatus,
                    isCompact: appState.isSessionActive
                )
                .offset(y: animateIn ? 0 : 16)
                .opacity(animateIn ? 1 : 0)
            }
            .disabled(showingEndSessionConfirmation)
            .blur(radius: showingEndSessionConfirmation ? 2 : 0)

            if showingEndSessionConfirmation {
                InlineConfirmationOverlay(
                    title: "Quit session early?",
                    message: "Ending now applies your configured early-exit XP penalty.",
                    confirmTitle: "Quit Session",
                    confirmStyle: .danger,
                    onConfirm: {
                        showingEndSessionConfirmation = false
                        appState.endSession(early: true)
                    },
                    onCancel: {
                        showingEndSessionConfirmation = false
                    }
                )
                .transition(.opacity)
            }

            // XP gain toast — appears when on-task XP is awarded
            if appState.lastXPGain > 0 {
                XPGainToast(xpGain: appState.lastXPGain)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .top).combined(with: .opacity)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }
        }
        .animation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.82), value: appState.lastXPGain)
        .padding(layoutPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            if reduceMotion {
                animateIn = true
            } else {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                    animateIn = true
                }
            }
        }
    }

    private var layoutSpacing: CGFloat {
        appState.isSessionActive ? 10 : AppTheme.sectionSpacing
    }

    private var layoutPadding: CGFloat {
        appState.isSessionActive ? AppTheme.chromePadding : AppTheme.windowPadding
    }

    private var contentTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98))
    }

    private var backendName: String {
        switch appState.primaryBackend {
        case "openai":
            return "OpenAI"
        case "ollama":
            return "Ollama"
        default:
            return "No AI"
        }
    }

    private func startSession() {
        appState.sessionGoal = appState.draftGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        appState.startSession()
    }

    private func pauseOrResume() {
        if appState.isPaused {
            appState.resumeSession()
        } else {
            appState.pauseSession()
        }
    }
}

private struct DashboardHeader: View {
    let isSessionActive: Bool
    let isCompact: Bool
    let showHome: () -> Void
    let showSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: isCompact ? 10 : 16) {
            LiquidIconButton("Home", icon: "chevron.left", size: isCompact ? 38 : AppTheme.controlMinHeight) {
                showHome()
            }

            VStack(alignment: .leading, spacing: isCompact ? 2 : 4) {
                HStack(spacing: isCompact ? 8 : 10) {
                    Image("CodeSergeantLogoInline")
                        .resizable()
                        .scaledToFit()
                        .frame(width: isCompact ? 28 : 34, height: isCompact ? 28 : 34)
                        .accessibilityHidden(true)

                    Text("Code Sergeant")
                        .font((isCompact ? Font.headline : .title2).weight(.black))
                        .foregroundStyle(.primary)
                }

                Text(isSessionActive ? "Session active" : "Ready to start")
                    .font(isCompact ? .caption : .subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            LiquidIconButton("Settings", icon: "gearshape.fill", size: isCompact ? 38 : AppTheme.controlMinHeight) {
                showSettings()
            }
        }
    }
}

private struct StartSessionPanel: View {
    @Binding var goalText: String
    @Binding var workMinutes: Double
    @Binding var breakMinutes: Double

    let isStartingSession: Bool
    let errorMessage: String?
    let startAction: () -> Void

    private var canStart: Bool {
        !goalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStartingSession
    }

    var body: some View {
        VStack(spacing: AppTheme.sectionSpacing) {
            HStack(alignment: .top, spacing: AppTheme.sectionSpacing) {
                HoverGlassCard(cornerRadius: 24) {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Mission", systemImage: "target")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        TextField("What do you want to accomplish?", text: $goalText, axis: .vertical)
                            .lineLimit(2...4)
                            .textFieldStyle(.plain)
                            .padding(14)
                            .frame(minHeight: 118, alignment: .topLeading)
                            .background {
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.white.opacity(0.06))
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(AppTheme.glassStroke, lineWidth: 1)
                            }
                    }
                    .padding(AppTheme.cardPadding)
                }
                .frame(maxWidth: .infinity, alignment: .top)

                HoverGlassCard(cornerRadius: 24) {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Session settings", systemImage: "slider.horizontal.3")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        TimerSlider(
                            label: "Work duration",
                            value: $workMinutes,
                            range: 15...60,
                            step: 5,
                            unit: "min"
                        )

                        Divider()

                        TimerSlider(
                            label: "Break duration",
                            value: $breakMinutes,
                            range: 5...15,
                            step: 5,
                            unit: "min"
                        )
                    }
                    .padding(AppTheme.cardPadding)
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }

            HStack(alignment: .center, spacing: 16) {
                LiquidButton(
                    isStartingSession ? "Starting…" : "Start Focus Session",
                    icon: isStartingSession ? "hourglass" : "play.fill",
                    style: .primary,
                    action: startAction
                )
                .disabled(!canStart)
                .opacity(canStart ? 1 : 0.72)

                if let errorMessage, !errorMessage.isEmpty {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.dangerTint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct ActiveSessionPanel: View {
    let goal: String
    let remainingSeconds: Int
    let totalSeconds: Int
    let isBreak: Bool
    let pomodoroState: String
    let sessionEndedEarly: Bool
    let totalXP: Int
    let sessionXP: Int
    let currentRank: String
    let rankProgress: Double
    let nextRankName: String
    let xpToNextRank: Int
    let focusTimeMinutes: Int
    let isPaused: Bool
    let pauseAction: () -> Void
    let endAction: () -> Void
    let skipAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                TimerDisplay(
                    remainingSeconds: remainingSeconds,
                    totalSeconds: totalSeconds,
                    isBreak: isBreak,
                    pomodoroState: pomodoroState,
                    sessionEndedEarly: sessionEndedEarly
                )
                .frame(width: 236)

                VStack(spacing: 10) {
                    HoverGlassCard(cornerRadius: 24) {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Current mission", systemImage: "target")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                Text(goal.isEmpty ? "No goal set" : goal)
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                            }

                            HStack(spacing: 10) {
                                StatCard(
                                    title: "Focus Time",
                                    value: "\(focusTimeMinutes)",
                                    detail: "min",
                                    tint: AppTheme.primaryTint,
                                    icon: "clock.fill"
                                )

                                StatCard(
                                    title: "Session XP",
                                    value: "+\(sessionXP)",
                                    detail: "earned",
                                    tint: AppTheme.warningTint,
                                    icon: "star.fill"
                                )
                            }

                            Divider()

                            XPDisplay(
                                totalXP: totalXP,
                                sessionXP: sessionXP,
                                currentRank: currentRank,
                                rankProgress: rankProgress,
                                nextRankName: nextRankName,
                                xpToNextRank: xpToNextRank,
                                isCompact: false
                            )
                        }
                        .padding(14)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }

            HStack(spacing: 10) {
                LiquidButton(
                    isPaused ? "Resume" : "Pause",
                    icon: isPaused ? "play.fill" : "pause.fill",
                    style: .secondary,
                    action: pauseAction
                )

                if let skipAction {
                    LiquidButton("Skip Break", icon: "forward.fill", style: .success, action: skipAction)
                }

                LiquidButton("Quit Session", icon: "stop.fill", style: .danger, action: endAction)
            }
        }
    }
}

private struct DashboardFooter: View {
    let backendName: String
    let screenMonitoringEnabled: Bool
    let lastJudgmentText: String
    let warningStatus: WarningStatus
    let isCompact: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 8) {
                FooterChip(
                    title: backendName,
                    icon: "cpu",
                    tint: AppTheme.primaryTint,
                    isCompact: isCompact
                )

                if screenMonitoringEnabled {
                    FooterChip(
                        title: "Screen Monitoring On",
                        icon: "eye.fill",
                        tint: AppTheme.canvasAccent,
                        isCompact: isCompact
                    )
                }

                FooterChip(
                    title: statusTitle,
                    icon: statusIcon,
                    tint: statusTint,
                    isCompact: isCompact
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !lastJudgmentText.isEmpty {
                Text(lastJudgmentText)
                    .font(isCompact ? .caption : .subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(isCompact ? 1 : 2)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusTitle: String {
        switch warningStatus {
        case .green:
            return "On Task"
        case .yellow:
            return "Thinking"
        case .red:
            return "Off Task"
        }
    }

    private var statusIcon: String {
        switch warningStatus {
        case .green:
            return "checkmark.circle.fill"
        case .yellow:
            return "exclamationmark.circle.fill"
        case .red:
            return "xmark.circle.fill"
        }
    }

    private var statusTint: Color {
        switch warningStatus {
        case .green:
            return AppTheme.successTint
        case .yellow:
            return AppTheme.warningTint
        case .red:
            return AppTheme.dangerTint
        }
    }
}

private struct FooterChip: View {
    let title: String
    let icon: String
    let tint: Color
    let isCompact: Bool

    var body: some View {
        Label(title, systemImage: icon)
            .font(isCompact ? .caption2 : .subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, isCompact ? 8 : 12)
            .padding(.vertical, isCompact ? 5 : 8)
            .background {
                Capsule()
                    .fill(.thinMaterial)
                    .overlay {
                        Capsule()
                            .stroke(tint.opacity(0.35), lineWidth: 1)
                    }
            }
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(value)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(tint)
                
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 60, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassCard(cornerRadius: 18)
    }
}

private struct XPGainToast: View {
    let xpGain: Int

    var body: some View {
        Label("+\(xpGain) XP", systemImage: "star.fill")
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(AppTheme.warningTint)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                Capsule()
                    .fill(.thinMaterial)
                    .overlay {
                        Capsule()
                            .stroke(AppTheme.warningTint.opacity(0.4), lineWidth: 1)
                    }
            }
            .accessibilityLabel("Gained \(xpGain) experience points")
    }
}

struct InlineConfirmationOverlay: View {
    let title: String
    let message: String
    let confirmTitle: String
    let confirmStyle: LiquidButton.ButtonStyle
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)

            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.headline)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    LiquidButton("Keep Going", style: .secondary, action: onCancel)
                    LiquidButton(confirmTitle, icon: "stop.fill", style: confirmStyle, action: onConfirm)
                }
            }
            .padding(20)
            .frame(width: 360)
            .glassCard(cornerRadius: 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    DashboardView()
        .environmentObject(AppState())
}
