//
//  GlassCard.swift
//  CodeSergeantUI
//
//  Liquid Glass card component with macOS Sonoma/Sequoia design
//

import SwiftUI

enum AppTheme {
    static let panelWidth: CGFloat = 820
    static let panelHeight: CGFloat = 430
    static let shellInset: CGFloat = 8
    static let chromePadding: CGFloat = 16
    static let windowPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 16
    static let cardPadding: CGFloat = 16
    static let compactSpacing: CGFloat = 12
    static let controlMinHeight: CGFloat = 42
    
    static let canvasTop = Color(red: 0.13, green: 0.16, blue: 0.19)
    static let canvasBottom = Color(red: 0.08, green: 0.10, blue: 0.12)
    static let canvasAccent = Color(red: 0.33, green: 0.41, blue: 0.28)
    static let primaryTint = Color(red: 0.31, green: 0.53, blue: 0.66)
    static let successTint = Color(red: 0.34, green: 0.56, blue: 0.42)
    static let dangerTint = Color(red: 0.70, green: 0.32, blue: 0.26)
    static let warningTint = Color(red: 0.75, green: 0.58, blue: 0.25)
    static let glassStroke = Color.white.opacity(0.18)
    static let glassHighlight = Color.white.opacity(0.08)
    static let panelShadow = Color.black.opacity(0.16)
}

// MARK: - Glass Card Modifier

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 18
    var backgroundOpacity: Double = 1
    var borderOpacity: Double = 1
    var shadowRadius: CGFloat = 14
    var isHovering: Bool = false
    
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.thinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(AppTheme.glassHighlight.opacity(backgroundOpacity))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [
                                AppTheme.glassStroke.opacity(borderOpacity),
                                Color.white.opacity(0.04),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isHovering ? 1.2 : 1
                    )
            }
            .shadow(
                color: AppTheme.panelShadow,
                radius: isHovering ? shadowRadius + 4 : shadowRadius,
                x: 0,
                y: isHovering ? 8 : 4
            )
            .scaleEffect(isHovering ? 1.01 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.82), value: isHovering)
    }
}

// MARK: - View Extension

extension View {
    /// Apply liquid glass card styling
    func glassCard(
        cornerRadius: CGFloat = 18,
        backgroundOpacity: Double = 1,
        borderOpacity: Double = 1,
        shadowRadius: CGFloat = 14,
        isHovering: Bool = false
    ) -> some View {
        modifier(GlassCard(
            cornerRadius: cornerRadius,
            backgroundOpacity: backgroundOpacity,
            borderOpacity: borderOpacity,
            shadowRadius: shadowRadius,
            isHovering: isHovering
        ))
    }
}

// MARK: - Hover Glass Card

/// A glass card that automatically handles hover state
struct HoverGlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let content: Content
    
    @State private var isHovering = false
    
    init(cornerRadius: CGFloat = 18, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }
    
    var body: some View {
        content
            .glassCard(cornerRadius: cornerRadius, isHovering: isHovering)
            .onHover { hovering in
                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                    isHovering = hovering
                }
            }
    }
}

// MARK: - Glass Background

/// Full-screen glass background with depth effect
struct GlassBackground: View {
    var opacity: Double = 0.85
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.canvasTop, AppTheme.canvasBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [AppTheme.canvasAccent.opacity(0.32), .clear],
                center: .topLeading,
                startRadius: 40,
                endRadius: 420
            )

            LinearGradient(
                colors: [
                    Color.white.opacity(0.05),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Rectangle()
                .fill(.regularMaterial)
                .opacity(opacity)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Animated Glass Border

/// Glass card with animated gradient border
struct AnimatedGlassBorder: ViewModifier {
    @State private var animationProgress: CGFloat = 0
    var cornerRadius: CGFloat = 18
    
    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                AppTheme.primaryTint.opacity(0.55),
                                AppTheme.canvasAccent.opacity(0.55),
                                Color.white.opacity(0.5),
                                AppTheme.primaryTint.opacity(0.55)
                            ]),
                            center: .center,
                            startAngle: .degrees(animationProgress * 360),
                            endAngle: .degrees(animationProgress * 360 + 360.0)
                        ),
                        lineWidth: 2
                    )
                    .opacity(0.4)
            }
            .onAppear {
                withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                    animationProgress = 1
                }
            }
    }
}

extension View {
    func animatedGlassBorder(cornerRadius: CGFloat = 18) -> some View {
        modifier(AnimatedGlassBorder(cornerRadius: cornerRadius))
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // Basic glass card
        Text("Basic Glass Card")
            .font(.headline)
            .padding(20)
            .glassCard()
        
        // Hover glass card
        HoverGlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Hover Glass Card")
                    .font(.headline)
                Text("Hover over me!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        
        // Animated border card
        Text("Animated Border")
            .font(.headline)
            .padding(20)
            .glassCard()
            .animatedGlassBorder()
    }
    .padding(40)
    .frame(width: 400, height: 400)
    .background(GlassBackground())
}
