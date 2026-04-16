//
//  XPDisplay.swift
//  CodeSergeantUI
//
//  XP and rank display with progress bar - military themed
//

import SwiftUI

/// XP and rank display with progress bar
struct XPDisplay: View {
    let totalXP: Int
    let sessionXP: Int
    let currentRank: String
    let rankProgress: Double
    let nextRankName: String
    let xpToNextRank: Int
    let isCompact: Bool
    
    var body: some View {
        if isCompact {
            compactView
        } else {
            fullView
        }
    }
    
    // MARK: - Compact View (Menu Bar)
    
    private var compactView: some View {
        HStack(spacing: 8) {
            Text(rankAbbreviation)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .tracking(1)
                .foregroundStyle(.white)
                .frame(width: 36, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [rankColor, rankColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
            
            // XP count with animation
            HStack(spacing: 2) {
                Text("\(totalXP)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3), value: totalXP)
                
                Text("XP")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            
            // Session XP (if active)
            if sessionXP > 0 {
                Text("+\(sessionXP)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.successTint)
                    .transition(.scale.combined(with: .opacity))
                    .animation(.spring(response: 0.3), value: sessionXP)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassCard(cornerRadius: 12, backgroundOpacity: 0.2)
    }
    
    // MARK: - Full View (Dashboard)
    
    private var fullView: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(spacing: 4) {
                Text(currentRank.uppercased())
                    .font(.system(size: 16, weight: .black, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [rankColor, rankColor.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                Text("\(totalXP) XP")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3), value: totalXP)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(rankColor.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(rankColor.opacity(0.3), lineWidth: 2)
                    )
            )
            
            if !nextRankName.isEmpty && xpToNextRank > 0 {
                VStack(alignment: .leading, spacing: 5) {
                    LabeledContent("Next: \(nextRankName.uppercased())") {
                        Text("\(xpToNextRank) XP")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    
                    ProgressView(value: rankProgress)
                        .tint(rankColor)
                    
                    Text("\(Int(rankProgress * 100))%")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    // MARK: - Helpers
    
    private var rankAbbreviation: String {
        // Get first 3 letters
        let abbr = String(currentRank.prefix(3)).uppercased()
        return abbr
    }
    
    private var rankColor: Color {
        // Color based on rank (military theme)
        switch currentRank.lowercased() {
        case "recruit":
            return .gray
        case "private":
            return AppTheme.primaryTint
        case "corporal":
            return AppTheme.canvasAccent
        case "sergeant":
            return AppTheme.successTint
        case "staff sergeant":
            return AppTheme.warningTint
        case "captain":
            return AppTheme.dangerTint
        default:
            return .white
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 30) {
        // Compact view
        XPDisplay(
            totalXP: 425,
            sessionXP: 12,
            currentRank: "Corporal",
            rankProgress: 0.42,
            nextRankName: "Sergeant",
            xpToNextRank: 175,
            isCompact: true
        )
        
        // Full view
        XPDisplay(
            totalXP: 425,
            sessionXP: 12,
            currentRank: "Corporal",
            rankProgress: 0.42,
            nextRankName: "Sergeant",
            xpToNextRank: 175,
            isCompact: false
        )
    }
    .padding(40)
    .frame(width: 400, height: 400)
    .background(GlassBackground())
}
