//
//  LiquidButton.swift
//  CodeSergeantUI
//
//  Liquid glass button with gradient, spring animations, and press effects
//

import SwiftUI

// MARK: - Liquid Button

struct LiquidButton: View {
    let title: String
    let icon: String?
    let style: ButtonStyle
    let action: () -> Void
    
    @State private var isHovering = false
    
    enum ButtonStyle: Equatable {
        case primary
        case secondary
        case success
        case danger
        case ghost
        
        var gradient: LinearGradient {
            switch self {
            case .primary:
                return LinearGradient(
                    colors: [AppTheme.primaryTint, AppTheme.canvasAccent],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .success:
                return LinearGradient(
                    colors: [AppTheme.successTint, AppTheme.canvasAccent.opacity(0.95)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .danger:
                return LinearGradient(
                    colors: [AppTheme.dangerTint, AppTheme.warningTint],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .secondary, .ghost:
                return LinearGradient(
                    colors: [Color.white.opacity(0.08), Color.white.opacity(0.03)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        
        var textColor: Color {
            switch self {
            case .ghost:
                return .primary
            default:
                return .white
            }
        }
    }
    
    init(
        _ title: String,
        icon: String? = nil,
        style: ButtonStyle = .primary,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                }

                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(style.textColor)
            .frame(maxWidth: .infinity)
            .frame(minHeight: AppTheme.controlMinHeight)
            .padding(.horizontal, 20)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(style.gradient)
                    .overlay {
                        if style == .secondary || style == .ghost {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(.thinMaterial)
                        }
                    }
                    .overlay {
                        if isHovering {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white.opacity(0.08))
                        }
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        style == .ghost ? AppTheme.glassStroke : Color.white.opacity(0.14),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: shadowColor,
                radius: isHovering ? 10 : 6,
                x: 0,
                y: isHovering ? 6 : 3
            )
            .scaleEffect(isHovering ? 1.01 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .animation(.spring(response: 0.22, dampingFraction: 0.84), value: isHovering)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .help(title)
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private var shadowColor: Color {
        switch style {
        case .primary:
            return AppTheme.primaryTint.opacity(0.22)
        case .success:
            return AppTheme.successTint.opacity(0.22)
        case .danger:
            return AppTheme.dangerTint.opacity(0.2)
        case .secondary, .ghost:
            return AppTheme.panelShadow
        }
    }
}

struct LiquidIconButton: View {
    let title: String
    let icon: String
    let size: CGFloat
    let action: () -> Void
    
    @State private var isHovering = false
    
    init(_ title: String, icon: String, size: CGFloat = AppTheme.controlMinHeight, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.size = size
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: size, height: size)
                .background {
                    Circle()
                        .fill(.thinMaterial)
                        .overlay {
                            Circle()
                                .stroke(AppTheme.glassStroke, lineWidth: 1)
                        }
                        .overlay {
                            if isHovering {
                                Circle()
                                    .fill(Color.white.opacity(0.08))
                            }
                        }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: size, height: size)
        .contentShape(Circle())
        .help(title)
        .accessibilityLabel(Text(title))
        .shadow(
            color: AppTheme.panelShadow,
            radius: isHovering ? 8 : 4,
            x: 0,
            y: isHovering ? 4 : 2
        )
        .scaleEffect(isHovering ? 1.03 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        LiquidButton("Start Focus Session", icon: "play.fill", style: .primary) {}
        
        LiquidButton("End Session", icon: "stop.fill", style: .danger) {}
        
        LiquidButton("Skip Break", icon: "forward.fill", style: .success) {}
        
        LiquidButton("Settings", icon: "gear", style: .secondary) {}
        
        LiquidButton("Cancel", style: .ghost) {}
        
        HStack(spacing: 12) {
            LiquidIconButton("Pause", icon: "pause.fill") {}
            LiquidIconButton("Play", icon: "play.fill") {}
            LiquidIconButton("Skip", icon: "forward.fill") {}
            LiquidIconButton("Settings", icon: "gear") {}
        }
    }
    .padding(40)
    .frame(width: 400, height: 500)
    .background(GlassBackground())
}
