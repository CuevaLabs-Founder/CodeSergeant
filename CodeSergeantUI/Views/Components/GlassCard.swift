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

    // Dark military green base — mirrors the site palette exactly
    static let canvasTop    = Color(red: 0.094, green: 0.125, blue: 0.086)  // #182016
    static let canvasBottom = Color(red: 0.059, green: 0.078, blue: 0.051)  // #0f140d
    static let canvasAccent = Color(red: 0.267, green: 0.329, blue: 0.227)  // #44543a camo dark
    static let primaryTint  = Color(red: 0.416, green: 0.498, blue: 0.298)  // #6a7f4c camo olive
    static let signalTint   = Color(red: 0.827, green: 1.000, blue: 0.451)  // #d3ff73 lime signal
    static let successTint  = Color(red: 0.353, green: 0.478, blue: 0.259)  // #5a7a42
    static let dangerTint   = Color(red: 0.700, green: 0.320, blue: 0.260)  // #b35242
    static let warningTint  = Color(red: 1.000, green: 0.561, blue: 0.353)  // #ff8f5a site warning
    static let glassStroke  = Color(red: 0.671, green: 0.722, blue: 0.576).opacity(0.18) // warm olive border
    static let glassHighlight = Color.white.opacity(0.05)
    static let panelShadow  = Color.black.opacity(0.22)
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
                                AppTheme.signalTint.opacity(0.12 * borderOpacity),
                                AppTheme.glassStroke.opacity(borderOpacity),
                                Color.white.opacity(0.03),
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
            // Dark military green base gradient — mirrors site linear-gradient
            LinearGradient(
                colors: [AppTheme.canvasTop, AppTheme.canvasBottom],
                startPoint: .top,
                endPoint: .bottom
            )

            // Lime signal glow at top — mirrors site radial-gradient at top
            RadialGradient(
                colors: [AppTheme.signalTint.opacity(0.10), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 280
            )

            // Warm amber accent top-right — mirrors site radial at 80% 20%
            RadialGradient(
                colors: [AppTheme.warningTint.opacity(0.07), .clear],
                center: UnitPoint(x: 0.88, y: 0.08),
                startRadius: 0,
                endRadius: 180
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
                                AppTheme.signalTint.opacity(0.55),
                                AppTheme.canvasAccent.opacity(0.55),
                                Color.white.opacity(0.4),
                                AppTheme.signalTint.opacity(0.55)
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
