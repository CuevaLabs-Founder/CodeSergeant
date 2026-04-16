//
//  TimerDisplay.swift
//  CodeSergeantUI
//
//  Liquid glass timer display with animations
//

import SwiftUI

// MARK: - Timer Display

struct TimerDisplay: View {
    let remainingSeconds: Int
    let totalSeconds: Int
    let isBreak: Bool
    
    private var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(totalSeconds - remainingSeconds) / Double(totalSeconds)
    }
    
    private var timeString: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    var body: some View {
        VStack(spacing: 10) {
            Circle()
                .trim(from: 0, to: 0.82)
                .stroke(Color.white.opacity(0.1), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .overlay {
                    Circle()
                        .trim(from: 0, to: min(max(progress, 0.02), 0.82))
                        .stroke(
                            LinearGradient(
                                colors: isBreak
                                    ? [AppTheme.successTint, AppTheme.canvasAccent]
                                    : [AppTheme.primaryTint, AppTheme.canvasAccent],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.35), value: progress)
                }
                .rotationEffect(.degrees(125))
                .frame(width: 140, height: 140)
                .overlay {
                    VStack(spacing: 4) {
                        Text(isBreak ? "BREAK" : "FOCUS")
                            .font(.caption2)
                            .bold()
                            .foregroundStyle(.secondary)
                        
                        Text(timeString)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: remainingSeconds)
                        
                        Text("\(Int(progress * 100))% complete")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            
            Text(isBreak ? "Take a breath, then get back in." : "Stay with the mission in front of you.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 180)
        }
        .padding(14)
        .glassCard(cornerRadius: 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isBreak ? "Break timer" : "Focus timer")
        .accessibilityValue("\(timeString), \(Int(progress * 100)) percent complete")
    }
}

struct CompactTimerDisplay: View {
    let remainingSeconds: Int
    let isBreak: Bool
    
    private var timeString: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    var body: some View {
        Label {
            HStack(spacing: 8) {
                Text(timeString)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                
                Text(isBreak ? "break" : "focus")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: isBreak ? "figure.mind.and.body" : "timer")
                .foregroundStyle(isBreak ? AppTheme.successTint : AppTheme.primaryTint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .glassCard(cornerRadius: 16)
    }
}

// MARK: - Timer Slider

struct TimerSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    
    init(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double = 5,
        unit: String = "min"
    ) {
        self.label = label
        self._value = value
        self.range = range
        self.step = step
        self.unit = unit
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent(label) {
                Text("\(Int(value)) \(unit)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .animation(.spring(response: 0.2), value: value)
            }
            
            Slider(value: $value, in: range, step: step)
                .tint(AppTheme.primaryTint)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 30) {
        TimerDisplay(
            remainingSeconds: 1234,
            totalSeconds: 1500,
            isBreak: false
        )
        
        CompactTimerDisplay(
            remainingSeconds: 234,
            isBreak: true
        )
        
        TimerSlider(
            label: "Work Duration",
            value: .constant(25),
            range: 15...60
        )
        .padding(.horizontal, 20)
        
        TimerSlider(
            label: "Break Duration",
            value: .constant(5),
            range: 5...15
        )
        .padding(.horizontal, 20)
    }
    .padding(40)
    .frame(width: 400, height: 600)
    .background(GlassBackground())
}
