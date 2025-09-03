import SwiftUI

/// Modern Login View with Clever Cloud Official Branding
struct LoginView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppCoordinator.self) private var coordinator
    
    // MARK: - Animation State
    @State private var logoScale: CGFloat = 0.8
    @State private var contentOpacity: Double = 0
    @State private var buttonHover: Bool = false
    
    var body: some View {
        ZStack {
            // Animated liquid background
            LiquidBackgroundView()
                .ignoresSafeArea()
            
            // Content overlay
            VStack(spacing: 0) {
                
                // Top spacing
                Spacer()
                    .frame(height: 60)
                
                // Logo section
                logoSection
                
                Spacer()
                
                // Authentication content
                authenticationSection
                
                Spacer()
                
                // Footer
                footerSection
                
                // Bottom spacing
                Spacer()
                    .frame(height: 40)
            }
            .opacity(contentOpacity)
        }
        .navigationBarHidden(true)
        .onAppear {
            RemoteLogger.shared.info("🔐 LoginView appeared", metadata: [
                "isAuthenticating": coordinator.oauthService.isAuthenticating ? "yes" : "no",
                "hasError": coordinator.oauthService.authError != nil ? "yes" : "no"
            ])
            startAppearanceAnimations()
        }
        .onChange(of: coordinator.oauthService.isAuthenticated) { oldValue, newValue in
            RemoteLogger.shared.debug("🔐 LoginView: Authentication state changed", metadata: [
                "oldValue": oldValue ? "authenticated" : "not authenticated",
                "newValue": newValue ? "authenticated" : "not authenticated"
            ])
            if newValue {
                handleSuccessfulAuthentication()
            }
        }
    }
    
    // MARK: - Logo Section
    private var logoSection: some View {
        VStack(spacing: 24) {
            // Clever Cloud Official Logo
            Image("CleverCloudLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 80)
                .scaleEffect(logoScale)
                .animation(.spring(response: 0.8, dampingFraction: 0.6, blendDuration: 0.3), value: logoScale)
            
            // Welcome text
            VStack(spacing: 12) {
                Text("Welcome to")
                    .font(.title2)
                    .fontWeight(.light)
                    .foregroundColor(.cleverNeutralWhite.opacity(0.9))
                
                Text("Clever Cloud Admin")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.cleverNeutralWhite)
                
                Text("Manage your applications, add-ons, and deployments")
                    .font(.subheadline)
                    .foregroundColor(.cleverNeutralWhite.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .padding(.horizontal, 24)
    }
    
    // MARK: - Authentication Section
    private var authenticationSection: some View {
        VStack(spacing: 32) {
            if coordinator.oauthService.isAuthenticating {
                authenticatingView
            } else {
                loginButton
            }
            
            // Error display
            if let error = coordinator.oauthService.authError {
                errorView(error: error)
            }
        }
        .padding(.horizontal, 32)
    }
    
    // MARK: - Authenticating View
    private var authenticatingView: some View {
        VStack(spacing: 24) {
            // Custom loading animation
            LoadingWaveView()
                .frame(height: 60)
            
            VStack(spacing: 12) {
                Text("Opening browser...")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.cleverNeutralWhite)
                
                Text("Complete the authentication in your browser, then return to the app.")
                    .font(.subheadline)
                    .foregroundColor(.cleverNeutralWhite.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 20)
    }
    
    // MARK: - Login Button
    private var loginButton: some View {
        Button(action: {
            RemoteLogger.shared.info("🔐 Login button tapped - Starting authentication")
            coordinator.oauthService.authenticate()
        }) {
            HStack(spacing: 12) {
                Image(systemName: "person.badge.key.fill")
                    .font(.system(size: 18, weight: .semibold))
                
                Text("Login with Clever Cloud")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.cleverNeutralWhite)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                LinearGradient.cleverLinearRed
                    .opacity(buttonHover ? 1.0 : 0.9)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.cleverNeutralWhite.opacity(0.2), lineWidth: 1)
            )
            .cornerRadius(16)
            .shadow(
                color: Color.cleverPrimary.opacity(0.3),
                radius: buttonHover ? 20 : 10,
                x: 0,
                y: buttonHover ? 8 : 4
            )
            .scaleEffect(buttonHover ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: buttonHover)
        }
        .onHover { hovering in
            buttonHover = hovering
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in buttonHover = true }
                .onEnded { _ in buttonHover = false }
        )
    }
    
    // MARK: - Error View
    private func errorView(error: String) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.cleverOrange)
                
                Text("Authentication Error")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.cleverNeutralWhite)
            }
            
            Text(error)
                .font(.subheadline)
                .foregroundColor(.cleverNeutralWhite.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            
            Button("Try Again") {
                coordinator.oauthService.authenticate()
            }
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(.cleverNeutralWhite)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.cleverOrange.opacity(0.8))
            .cornerRadius(12)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.cleverNeutralBlack.opacity(0.3))
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.cleverOrange.opacity(0.3), lineWidth: 1)
                )
        )
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }
    
    // MARK: - Footer Section
    private var footerSection: some View {
        VStack(spacing: 16) {
            // Security badge
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(.cleverProductGreen)
                
                Text("Secure OAuth Authentication")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.cleverNeutralWhite.opacity(0.9))
            }
            
            Text("Uses the same authentication method as the official Clever Cloud CLI tools")
                .font(.caption2)
                .foregroundColor(.cleverNeutralWhite.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            // Troubleshooting help
            if coordinator.oauthService.authError != nil {
                VStack(spacing: 8) {
                    Text("Having trouble?")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.cleverOrange)
                    
                    Text("Try disabling 'Prevent Cross-Site Tracking' in Settings > Safari")
                        .font(.caption2)
                        .foregroundColor(.cleverNeutralWhite.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .padding(.top, 8)
            }
        }
    }
    
    // MARK: - Animation Methods
    private func startAppearanceAnimations() {
        // Logo scale animation
        withAnimation(.spring(response: 1.0, dampingFraction: 0.8, blendDuration: 0.3).delay(0.2)) {
            logoScale = 1.0
        }
        
        // Content fade in
        withAnimation(.easeInOut(duration: 1.0).delay(0.4)) {
            contentOpacity = 1.0
        }
    }
    
    private func handleSuccessfulAuthentication() {
        RemoteLogger.shared.info("✅ LoginView: Authentication successful, dismissing view")
        // Force authentication check in coordinator
        coordinator.forceAuthenticationCheck()
        
        // Dismiss with animation delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            dismiss()
        }
    }
}

// MARK: - Loading Wave Animation
struct LoadingWaveView: View {
    @State private var animationPhase: Double = 0
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<5) { index in
                Circle()
                    .fill(Color.cleverNeutralWhite)
                    .frame(width: 12, height: 12)
                    .scaleEffect(
                        1.0 + 0.5 * sin(animationPhase + Double(index) * 0.6)
                    )
                    .opacity(
                        0.5 + 0.5 * sin(animationPhase + Double(index) * 0.6)
                    )
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                animationPhase = 2 * .pi
            }
        }
    }
}

// MARK: - Preview
#Preview {
    LoginView()
        .environment(AppCoordinator())
} 