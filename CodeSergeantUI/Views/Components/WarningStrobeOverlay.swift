//
//  WarningStrobeOverlay.swift
//  CodeSergeantUI
//
//  Flashing border overlay for warning states (green/yellow/red)
//

import SwiftUI

/// Flashing border overlay for warning states
struct WarningStrobeOverlay: ViewModifier {
    let status: WarningStatus
    @State private var isFlashing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    
    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(strokeColor, lineWidth: strokeWidth)
                    .opacity(borderOpacity)
                    .animation(
                        shouldFlash
                            ? .easeInOut(duration: 0.5).repeatForever(autoreverses: true)
                            : .easeInOut(duration: 0.2),
                        value: isFlashing
                    )
            }
            .overlay(alignment: .topTrailing) {
                if differentiateWithoutColor {
                    Image(systemName: statusIcon)
                        .font(.caption.bold())
                        .foregroundStyle(strokeColor)
                        .padding(8)
                }
            }
            .onChange(of: status) {
                isFlashing = shouldFlash
            }
            .onAppear {
                isFlashing = shouldFlash
            }
    }
    
    private var strokeColor: Color {
        switch status {
        case .green:
            return AppTheme.successTint
        case .yellow:
            return AppTheme.warningTint
        case .red:
            return AppTheme.dangerTint
        }
    }
    
    private var strokeWidth: CGFloat {
        switch status {
        case .green:
            return 2
        case .yellow:
            return 3
        case .red:
            return 4
        }
    }
    
    private var borderOpacity: Double {
        if shouldFlash {
            return isFlashing ? 0.95 : 0.28
        }
        
        switch status {
        case .green:
            return 0.45
        case .yellow:
            return 0.65
        case .red:
            return 0.9
        }
    }
    
    private var shouldFlash: Bool {
        status == .red && !reduceMotion
    }
    
    private var statusIcon: String {
        switch status {
        case .green:
            return "checkmark.circle.fill"
        case .yellow:
            return "exclamationmark.circle.fill"
        case .red:
            return "xmark.circle.fill"
        }
    }
}

extension View {
    /// Apply warning strobe border based on status
    func warningStrobe(status: WarningStatus) -> some View {
        modifier(WarningStrobeOverlay(status: status))
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 30) {
        // Green - on task
        Text("On Task")
            .font(.system(size: 26, weight: .bold))
            .frame(width: 200, height: 100)
            .background(.ultraThinMaterial)
            .clipShape(.rect(cornerRadius: 12))
            .warningStrobe(status: .green)
        
        // Yellow - thinking
        Text("Thinking")
            .font(.system(size: 26, weight: .bold))
            .frame(width: 200, height: 100)
            .background(.ultraThinMaterial)
            .clipShape(.rect(cornerRadius: 12))
            .warningStrobe(status: .yellow)
        
        // Red - off task (flashing)
        Text("Off Task")
            .font(.system(size: 26, weight: .bold))
            .frame(width: 200, height: 100)
            .background(.ultraThinMaterial)
            .clipShape(.rect(cornerRadius: 12))
            .warningStrobe(status: .red)
    }
    .padding(40)
    .background(GlassBackground())
}
