import SwiftUI

// MARK: - Clever Cloud Official Colors
// Based on Clever Cloud Style Guide: https://www.clever-cloud.com/style-guide/

extension Color {
    
    // MARK: - Base Colors
    static let cleverPrimary = Color(hex: "#a51050")        // $color-primary
    static let cleverPurple = Color(hex: "#3a3871")         // $color-purple  
    static let cleverCherry = Color(hex: "#a51050")         // $color-cherry
    static let cleverOrange = Color(hex: "#f57461")         // $color-orange
    static let cleverRed1 = Color(hex: "#e63f48")           // $color-red-1
    static let cleverRed2 = Color(hex: "#de233c")           // $color-red-2
    static let cleverRed3 = Color(hex: "#cb1c42")           // $color-red-3
    
    // MARK: - Neutral Colors
    static let cleverNeutralGrey = Color(hex: "#73738e")     // $color-neutral-grey
    static let cleverNeutralWhite = Color(hex: "#fff")       // $color-neutral-white
    static let cleverNeutralBlack = Color(hex: "#13172e")    // $color-neutral-black
    static let cleverNeutralGreyLight = Color(hex: "#f9f9fb") // $color-neutral-greylight
    static let cleverNeutralPurpleGrey = Color(hex: "#deddee") // $color-neutral-purplegrey
    
    // MARK: - Tint Colors
    static let cleverTintBlack = Color(hex: "#1c2045")       // $color-tint-black
    static let cleverTintWhite = Color(hex: "#f1f0fb")       // $color-tint-white
    
    // MARK: - Blur Colors
    static let cleverBlurPurple = Color(hex: "#5754aa")      // $color-blur-purple
    
    // MARK: - Product Colors
    static let cleverProductGreen = Color(hex: "#11bea9")    // $color-product-green
    static let cleverProductOrange = Color(hex: "#f57461")   // $color-product-orange
    static let cleverProductPurple = Color(hex: "#4e4ed9")   // $color-product-purple
    static let cleverProductGreenApple = Color(hex: "#11aa20") // $color-product-greenapple
    
    // MARK: - Gradient Colors for Animations
    static let cleverGradientColors: [Color] = [
        .cleverPrimary,
        .cleverPurple,
        .cleverOrange,
        .cleverRed1,
        .cleverRed2,
        .cleverRed3,
        .cleverProductPurple,
        .cleverBlurPurple
    ]
}

// MARK: - Color Extension for Hex Support
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Linear Gradients
extension LinearGradient {
    
    // Clever Cloud Linear Red: linear-gradient(90deg,#f57461,#cb1c42 50.48%,#a51050)
    static let cleverLinearRed = LinearGradient(
        gradient: Gradient(colors: [
            Color.cleverOrange,
            Color.cleverRed3,
            Color.cleverPrimary
        ]),
        startPoint: .leading,
        endPoint: .trailing
    )
    
    // Clever Cloud Linear Orange: linear-gradient(90deg,#a51050,#cb1c42 50.48%,#f57461)
    static let cleverLinearOrange = LinearGradient(
        gradient: Gradient(colors: [
            Color.cleverPrimary,
            Color.cleverRed3,
            Color.cleverOrange
        ]),
        startPoint: .leading,
        endPoint: .trailing
    )
    
    // Animated Liquid Background
    static let cleverLiquidBackground = LinearGradient(
        gradient: Gradient(colors: Color.cleverGradientColors),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
} 