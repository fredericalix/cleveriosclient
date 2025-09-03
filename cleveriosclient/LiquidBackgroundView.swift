import SwiftUI

// MARK: - Liquid Background Animation View
// Creates a dynamic, flowing background animation using Clever Cloud brand colors

struct LiquidBackgroundView: View {
    
    // MARK: - Animation State
    @State private var animationOffset1: CGFloat = 0
    @State private var animationOffset2: CGFloat = 0
    @State private var animationOffset3: CGFloat = 0
    
    // Static color combinations for consistent branding
    private let colorSet1: [Color] = [.cleverPrimary, .cleverPurple]
    private let colorSet2: [Color] = [.cleverOrange, .cleverRed1]
    private let colorSet3: [Color] = [.cleverProductPurple, .cleverBlurPurple]
    
    // MARK: - Body
    var body: some View {
        ZStack {
            // Base background
            Color.cleverNeutralBlack
                .ignoresSafeArea()
            
            // Animated liquid layers
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                
                // Layer 1 - Primary wave
                liquidWave(
                    colors: colorSet1,
                    offset: animationOffset1,
                    amplitude: height * 0.1,
                    frequency: 1.5,
                    opacity: 0.8
                )
                .frame(width: width * 1.5, height: height * 1.2)
                .offset(x: -width * 0.25, y: animationOffset1 * 0.3)
                
                // Layer 2 - Secondary wave
                liquidWave(
                    colors: colorSet2,
                    offset: animationOffset2,
                    amplitude: height * 0.08,
                    frequency: 2.0,
                    opacity: 0.6
                )
                .frame(width: width * 1.3, height: height * 1.1)
                .offset(x: -width * 0.15, y: animationOffset2 * 0.4)
                
                // Layer 3 - Tertiary wave
                liquidWave(
                    colors: colorSet3,
                    offset: animationOffset3,
                    amplitude: height * 0.06,
                    frequency: 2.5,
                    opacity: 0.4
                )
                .frame(width: width * 1.2, height: height)
                .offset(x: -width * 0.1, y: animationOffset3 * 0.2)
            }
            
            // Overlay gradient for depth
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.cleverNeutralBlack.opacity(0.3),
                    Color.clear,
                    Color.cleverNeutralBlack.opacity(0.2)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .onAppear {
            startAnimations()
        }
    }
    
    // MARK: - Liquid Wave Generator
    private func liquidWave(
        colors: [Color],
        offset: CGFloat,
        amplitude: CGFloat,
        frequency: Double,
        opacity: Double
    ) -> some View {
        LinearGradient(
            gradient: Gradient(colors: colors),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .clipShape(
            LiquidShape(
                offset: offset,
                amplitude: amplitude,
                frequency: frequency
            )
        )
        .opacity(opacity)
        .blur(radius: 20)
    }
    
    // MARK: - Start Animations
    private func startAnimations() {
        // Wave animations
        withAnimation(
            Animation.easeInOut(duration: 8.0).repeatForever(autoreverses: true)
        ) {
            animationOffset1 = 100
        }
        
        withAnimation(
            Animation.easeInOut(duration: 6.0).repeatForever(autoreverses: true).delay(1.0)
        ) {
            animationOffset2 = 80
        }
        
        withAnimation(
            Animation.easeInOut(duration: 10.0).repeatForever(autoreverses: true).delay(2.0)
        ) {
            animationOffset3 = 60
        }
    }
}

// MARK: - Liquid Shape
struct LiquidShape: Shape {
    let offset: CGFloat
    let amplitude: CGFloat
    let frequency: Double
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        
        path.move(to: CGPoint(x: 0, y: height))
        
        for x in stride(from: 0, through: width, by: 1) {
            let relativeX = x / width
            let sine = sin(relativeX * frequency * 2 * .pi + offset * 0.02)
            let y = amplitude * sine + height * 0.5
            path.addLine(to: CGPoint(x: x, y: y))
        }
        
        path.addLine(to: CGPoint(x: width, y: height))
        path.addLine(to: CGPoint(x: 0, y: height))
        path.closeSubpath()
        
        return path
    }
}

// MARK: - Preview
#Preview {
    LiquidBackgroundView()
} 