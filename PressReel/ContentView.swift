//
//  ContentView.swift
//  PressReel
//
//  Created by Ameer Alnseirat on 2/3/25.
//

import SwiftUI
import AuthenticationServices
import FirebaseAuth
import GoogleSignIn

struct OnboardingPage: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let imageName: String
    let color: Color
}

struct ContentView: View {
    @StateObject private var authService = AuthenticationService()
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var isAnimating = false
    @State private var showSignUp = false
    @State private var showLogin = false
    @State private var currentPage = 0
    
    private let onboardingPages = [
        OnboardingPage(
            title: "Create Amazing Videos",
            description: "Transform your ideas into stunning videos with our powerful editing tools",
            imageName: "video.badge.plus",
            color: .red
        ),
        OnboardingPage(
            title: "Share Your Story",
            description: "Connect with your audience through engaging video content",
            imageName: "person.2.wave.2",
            color: .orange
        ),
        OnboardingPage(
            title: "Grow Your Presence",
            description: "Build your brand and reach new heights with PressReel",
            imageName: "chart.line.uptrend.xyaxis",
            color: .purple
        )
    ]
    
    var body: some View {
        Group {
            if authService.user != nil {
                MainTabView()
            } else if !hasSeenOnboarding {
                OnboardingPagesView(pages: onboardingPages, currentPage: $currentPage) {
                    withAnimation {
                        hasSeenOnboarding = true
                    }
                }
            } else {
                LandingView(isAnimating: $isAnimating, showSignUp: $showSignUp, showLogin: $showLogin)
            }
        }
    }
}

struct OnboardingPagesView: View {
    let pages: [OnboardingPage]
    @Binding var currentPage: Int
    let onFinish: () -> Void
    
    @State private var pageOffset: CGFloat = 0
    @State private var dragOffset: CGFloat = 0
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    ForEach(pages.indices, id: \.self) { index in
                        OnboardingPageView(page: pages[index])
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: UIScreen.main.bounds.height * 0.7)
                
                // Page Control dots
                HStack(spacing: 12) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Circle()
                            .fill(currentPage == index ? Color.white : Color.white.opacity(0.5))
                            .frame(width: 8, height: 8)
                            .scaleEffect(currentPage == index ? 1.2 : 1.0)
                            .animation(.spring(), value: currentPage)
                    }
                }
                .padding(.top, 20)
                
                // Next/Finish button
                Button(action: {
                    if currentPage < pages.count - 1 {
                        withAnimation {
                            currentPage += 1
                        }
                    } else {
                        onFinish()
                    }
                }) {
                    Text(currentPage < pages.count - 1 ? "Next" : "Get Started")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 30)
                .padding(.top, 30)
                
                if currentPage < pages.count - 1 {
                    Button("Skip") {
                        onFinish()
                    }
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.top, 20)
                }
            }
            .padding(.bottom, 50)
        }
    }
}

struct OnboardingPageView: View {
    let page: OnboardingPage
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: page.imageName)
                .font(.system(size: 100))
                .foregroundColor(page.color)
                .scaleEffect(isAnimating ? 1 : 0.5)
                .opacity(isAnimating ? 1 : 0)
            
            VStack(spacing: 12) {
                Text(page.title)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .offset(x: isAnimating ? 0 : UIScreen.main.bounds.width)
                
                Text(page.description)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                    .offset(x: isAnimating ? 0 : -UIScreen.main.bounds.width)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) {
                isAnimating = true
            }
        }
        .onDisappear {
            isAnimating = false
        }
    }
}

struct MainTabView: View {
    @State private var selectedTab = 0
    @StateObject private var authService = AuthenticationService()
    @State private var isRecording = false
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                TabView(selection: $selectedTab) {
                    FeedView(userId: authService.user?.uid ?? "")
                        .navigationBarHidden(true)
                        .tag(0)
                    
                    Group {
                        CreateView()
                            .navigationBarHidden(true)
                    }
                    .tag(1)
                    
                    LibraryView()
                        .navigationBarHidden(true)
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .background(Color.black)
                
                // Custom Tab Bar
                CustomTabBar(selectedTab: $selectedTab, isRecording: $isRecording)
            }
            .ignoresSafeArea(.keyboard)
            .background(Color.black)
        }
        .preferredColorScheme(.dark)
    }
}

struct CustomTabBar: View {
    @Binding var selectedTab: Int
    @Binding var isRecording: Bool
    @Namespace private var animation
    
    var body: some View {
        HStack(spacing: 0) {
            // Feed Tab
            TabBarButton(
                isSelected: selectedTab == 0,
                icon: "newspaper.fill",
                title: "Feed",
                namespace: animation
            ) {
                withAnimation(.spring()) {
                    selectedTab = 0
                    isRecording = false
                }
            }
            .opacity(selectedTab == 1 ? 0.5 : 1)
            
            // Create Button (Center)
            CreateButton(isRecording: selectedTab == 1) {
                withAnimation(.spring()) {
                    if selectedTab == 1 {
                        selectedTab = 0
                    } else {
                        selectedTab = 1
                    }
                }
            }
            .offset(y: -20)
            
            // Library Tab
            TabBarButton(
                isSelected: selectedTab == 2,
                icon: "folder.fill",
                title: "Library",
                namespace: animation
            ) {
                withAnimation(.spring()) {
                    selectedTab = 2
                    isRecording = false
                }
            }
            .opacity(selectedTab == 1 ? 0.5 : 1)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(Color.black)
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.05))
                )
                .shadow(color: .black.opacity(0.5), radius: 10, y: -5)
                .ignoresSafeArea()
        )
    }
}

struct TabBarButton: View {
    let isSelected: Bool
    let icon: String
    let title: String
    let namespace: Namespace.ID
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                
                Text(title)
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .foregroundColor(isSelected ? .red : .white.opacity(0.7))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.1))
                        .matchedGeometryEffect(id: "TAB", in: namespace)
                }
            }
        }
    }
}

struct CreateButton: View {
    let isRecording: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 60, height: 60)
                    .shadow(color: .red.opacity(0.3), radius: 10, x: 0, y: 5)
                
                if isRecording {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .frame(width: 100)
    }
}

struct LandingView: View {
    @Binding var isAnimating: Bool
    @Binding var showSignUp: Bool
    @Binding var showLogin: Bool
    @State private var gradientRotation: Double = 0
    @State private var hoveredFeature: Int? = nil
    
    let timer = Timer.publish(every: 0.02, on: .main, in: .common).autoconnect()
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Dynamic Background
                Color.black.ignoresSafeArea()
                
                // Animated Gradient Background
                RadialGradient(
                    gradient: Gradient(colors: [Color.red.opacity(0.3), .clear]),
                    center: .center,
                    startRadius: 0,
                    endRadius: geometry.size.width
                )
                .rotationEffect(.degrees(gradientRotation))
                .ignoresSafeArea()
                .opacity(0.4)
                
                // Main Content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Logo Section with Glowing Effect
                        ZStack {
                            // Glow Effect
                            Circle()
                                .fill(Color.red.opacity(0.15))
                                .frame(width: 200, height: 200)
                                .blur(radius: 30)
                                .opacity(isAnimating ? 1 : 0)
                            
                            VStack(spacing: 15) {
                                HStack(spacing: 0) {
                                    Text("Press")
                                        .font(.system(size: 48, weight: .black))
                                        .foregroundColor(.white)
                                    
                                    Text("Reel")
                                        .font(.system(size: 48, weight: .black))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.red)
                                                .shadow(color: Color.red.opacity(0.5), radius: 10, x: 0, y: 0)
                                        )
                                }
                                .opacity(isAnimating ? 1 : 0)
                                .scaleEffect(isAnimating ? 1 : 0.8)
                                
                                Text("News Video Editor")
                                    .font(.title3)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white.opacity(0.9))
                                    .opacity(isAnimating ? 1 : 0)
                            }
                        }
                        .padding(.top, 60)
                        .padding(.bottom, 60)
                        
                        // Main Features with Modern Cards
                        VStack(spacing: 20) {
                            FeatureCard(index: 0, icon: "wand.and.stars", title: "AI-Powered Editing", description: "Let AI transform your footage into compelling stories", isHovered: hoveredFeature == 0)
                                .onHover { isHovered in
                                    withAnimation(.spring()) {
                                        hoveredFeature = isHovered ? 0 : nil
                                    }
                                }
                            
                            FeatureCard(index: 1, icon: "clock.fill", title: "Quick Turnaround", description: "Create professional videos in minutes, not hours", isHovered: hoveredFeature == 1)
                                .onHover { isHovered in
                                    withAnimation(.spring()) {
                                        hoveredFeature = isHovered ? 1 : nil
                                    }
                                }
                            
                            FeatureCard(index: 2, icon: "sparkles.tv.fill", title: "Professional Output", description: "Broadcast-ready videos with stunning quality", isHovered: hoveredFeature == 2)
                                .onHover { isHovered in
                                    withAnimation(.spring()) {
                                        hoveredFeature = isHovered ? 2 : nil
                                    }
                                }
                        }
                        .opacity(isAnimating ? 1 : 0)
                        .offset(y: isAnimating ? 0 : 40)
                    
                        // Action Buttons with Glass Effect
                        VStack(spacing: 20) {
                            Button(action: { showSignUp.toggle() }) {
                                Text("Get Started")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 60)
                                    .background(
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 20)
                                                .fill(Color.red)
                                            
                                            // Shine effect
                                            RoundedRectangle(cornerRadius: 20)
                                                .fill(
                                                    LinearGradient(gradient: 
                                                        Gradient(colors: [.white.opacity(0.2), .clear]),
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing)
                                                )
                                        }
                                    )
                                    .shadow(color: Color.red.opacity(0.5), radius: 20, x: 0, y: 10)
                            }
                            .buttonStyle(ScaleButtonStyle())
                            
                            Button(action: { showLogin.toggle() }) {
                                Text("Sign In")
                                    .font(.title3)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 60)
                                    .background(
                                        RoundedRectangle(cornerRadius: 20)
                                            .fill(Color.white.opacity(0.05))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 20)
                                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                            )
                                    )
                            }
                            .buttonStyle(ScaleButtonStyle())
                        }
                        .padding(.horizontal, 30)
                        .padding(.top, 60)
                        .padding(.bottom, 40)
                    .opacity(isAnimating ? 1 : 0)
                    .offset(y: isAnimating ? 0 : 20)
                }
                .padding(.bottom, 50)
                .padding(.horizontal)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) {
                isAnimating = true
            }
        }
        .onReceive(timer) { _ in
            withAnimation {
                gradientRotation += 0.1
            }
        }
        .sheet(isPresented: $showSignUp) {
            AuthView(isLogin: false)
        }
        .sheet(isPresented: $showLogin) {
            AuthView(isLogin: true)
        }
    }
}

// Modern Feature Card
struct FeatureCard: View {
    let index: Int
    let icon: String
    let title: String
    let description: String
    let isHovered: Bool
    
    var body: some View {
        HStack(spacing: 25) {
            // Icon with animated background
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.1))
                    .frame(width: 70, height: 70)
                
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundColor(.red)
                    .symbolEffect(.bounce, options: .repeating, value: isHovered)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(2)
            }
            
            Spacer()
        }
        .padding(.vertical, 25)
        .padding(.horizontal, 25)
        .background(
            RoundedRectangle(cornerRadius: 25)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 25)
                        .stroke(LinearGradient(
                            gradient: Gradient(colors: [.red.opacity(isHovered ? 0.5 : 0.1), .clear]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ), lineWidth: 1)
                )
        )
        .shadow(color: .red.opacity(isHovered ? 0.1 : 0), radius: 20, x: 0, y: 10)
        .scaleEffect(isHovered ? 1.02 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .padding(.horizontal)
    }
}

// Custom Button Style with Scale Animation
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
}

struct PasswordStrengthView: View {
    let password: String
    
    private var strength: (value: Double, text: String, color: Color) {
        let hasUppercase = password.contains(where: { $0.isUppercase })
        let hasLowercase = password.contains(where: { $0.isLowercase })
        let hasNumbers = password.contains(where: { $0.isNumber })
        let hasSpecialCharacters = password.contains(where: { "!@#$%^&*()_+-=[]{}|;:,.<>?".contains($0) })
        let length = password.count
        
        var score = 0.0
        if length >= 8 { score += 0.2 }
        if length >= 12 { score += 0.2 }
        if hasUppercase { score += 0.2 }
        if hasLowercase { score += 0.2 }
        if hasNumbers { score += 0.1 }
        if hasSpecialCharacters { score += 0.1 }
        
        let text: String
        let color: Color
        switch score {
        case 0..<0.3:
            text = "Weak"
            color = .red
        case 0.3..<0.6:
            text = "Medium"
            color = .orange
        case 0.6..<0.8:
            text = "Strong"
            color = .yellow
        default:
            text = "Very Strong"
            color = .green
        }
        
        return (score, text, color)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .frame(width: geometry.size.width, height: 4)
                        .opacity(0.2)
                        .foregroundColor(.gray)
                    
                    Rectangle()
                        .frame(width: geometry.size.width * strength.value, height: 4)
                        .foregroundColor(strength.color)
                        .animation(.easeInOut, value: strength.value)
                }
            }
            .frame(height: 4)
            
            Text(strength.text)
                .font(.caption)
                .foregroundColor(strength.color)
        }
    }
}

struct AuthView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var authService = AuthenticationService()
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var showError = false
    let isLogin: Bool
    
    private var isFormValid: Bool {
        if isLogin {
            return !email.isEmpty && !password.isEmpty
        } else {
            return !firstName.isEmpty && !lastName.isEmpty && 
                   !email.isEmpty && !password.isEmpty && 
                   password == confirmPassword && 
                   password.count >= 8
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 30) {
                        Text(isLogin ? "Welcome Back" : "Create Account")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        VStack(spacing: 16) {
                            if !isLogin {
                                TextField("", text: $firstName)
                                    .textFieldStyle(CustomTextFieldStyle())
                                    .textContentType(.givenName)
                                    .customPlaceholder("First Name", text: $firstName)
                                
                                TextField("", text: $lastName)
                                    .textFieldStyle(CustomTextFieldStyle())
                                    .textContentType(.familyName)
                                    .customPlaceholder("Last Name", text: $lastName)
                            }
                            
                            TextField("", text: $email)
                                .textFieldStyle(CustomTextFieldStyle())
                                .autocapitalization(.none)
                                .keyboardType(.emailAddress)
                                .textContentType(isLogin ? .emailAddress : .username)
                                .customPlaceholder("Email", text: $email)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                SecureField("", text: $password)
                                    .textFieldStyle(CustomTextFieldStyle())
                                    .textContentType(isLogin ? .password : .newPassword)
                                    .customPlaceholder("Password", text: $password)
                                
                                if !isLogin {
                                    PasswordStrengthView(password: password)
                                        .padding(.horizontal, 4)
                                    
                                    SecureField("", text: $confirmPassword)
                                        .textFieldStyle(CustomTextFieldStyle())
                                        .textContentType(.newPassword)
                                        .customPlaceholder("Confirm Password", text: $confirmPassword)
                                    
                                    if !confirmPassword.isEmpty && password != confirmPassword {
                                        Text("Passwords do not match")
                                            .font(.caption)
                                            .foregroundColor(.red)
                                            .padding(.leading, 4)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        // Email Sign In/Up Button
                        Button(action: {
                            Task {
                                await handleEmailAuth()
                            }
                        }) {
                            ZStack {
                                Text(isLogin ? "Sign In" : "Sign Up")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 54)
                                    .background(isFormValid ? Color.red : Color.red.opacity(0.5))
                                    .cornerRadius(16)
                                    .opacity(isLoading ? 0 : 1)
                                
                                if isLoading {
                                    ProgressView()
                                        .tint(.white)
                                }
                            }
                        }
                        .disabled(!isFormValid || isLoading)
                        .padding(.horizontal)
                        
                        // Divider with "or" text
                        HStack {
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(.white.opacity(0.3))
                            
                            Text("or")
                                .foregroundColor(.white.opacity(0.6))
                                .padding(.horizontal)
                            
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(.white.opacity(0.3))
                        }
                        .padding(.horizontal)
                        
                        // Social Sign In Buttons
                        VStack(spacing: 12) {
                            Button(action: {
                                Task {
                                    await handleGoogleSignIn()
                                }
                            }) {
                                HStack {
                                    Image(systemName: "g.circle.fill")
                                        .foregroundColor(.white)
                                    Text("Continue with Google")
                                        .foregroundColor(.white)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(16)
                            }
                        }
                        .padding(.horizontal)
                        
                        if isLogin {
                            Button("Forgot Password?") {
                                // Handle forgot password
                            }
                            .foregroundColor(.red)
                        }
                        
                        Spacer()
                    }
                    .padding(.top, 50)
                }
            }
            .navigationBarItems(trailing: Button("Close") {
                dismiss()
            }
            .foregroundColor(.white))
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(authService.errorMessage ?? "An error occurred")
            }
        }
    }
    
    private func handleEmailAuth() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            if isLogin {
                try await authService.signInWithEmail(email: email, password: password)
            } else {
                try await authService.signUpWithEmail(
                    email: email,
                    password: password,
                    firstName: firstName,
                    lastName: lastName
                )
            }
            dismiss()
        } catch {
            showError = true
        }
    }
    
    private func handleGoogleSignIn() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await authService.signInWithGoogle()
            dismiss()
        } catch {
            showError = true
        }
    }
}

struct CustomTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding()
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)
            .foregroundColor(.white)
            .accentColor(.red)
            .tint(.red)
    }
}

extension View {
    func customPlaceholder(_ text: String, text binding: Binding<String>) -> some View {
        self.modifier(PlaceholderViewModifier(placeholder: text, text: binding))
    }
}

struct PlaceholderViewModifier: ViewModifier {
    let placeholder: String
    @Binding var text: String
    
    init(placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        self._text = text
    }
    
    func body(content: Content) -> some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundColor(Color.white.opacity(0.6))
                    .padding(.leading, 16)
            }
            content
        }
    }
}

struct ProfileView: View {
    @Binding var isPresented: Bool
    @StateObject private var authService = AuthenticationService()
    @State private var showError = false
    @State private var showScripts = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Profile Image
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 100, height: 100)
                        .overlay(
                            Text(String((authService.user?.displayName?.prefix(1) ?? "U").uppercased()))
                                .font(.system(size: 40, weight: .bold))
                                .foregroundColor(.white)
                        )
                    
                    // User Info
                    VStack(spacing: 8) {
                        Text(authService.user?.displayName ?? "User")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text(authService.user?.email ?? "")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    Spacer()
                    
                    // Scripts Button
                    Button(action: { showScripts = true }) {
                        HStack {
                            Image(systemName: "doc.text")
                            Text("My Scripts")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.05))
                        )
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    // Sign Out Button
                    Button(action: {
                        do {
                            try authService.signOut()
                            isPresented = false
                        } catch {
                            showError = true
                        }
                    }) {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Sign Out")
                        }
                        .foregroundColor(.red)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.red, lineWidth: 1)
                        )
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
                .padding(.top, 32)
            }
            .navigationBarItems(trailing: Button("Close") {
                isPresented = false
            }
            .foregroundColor(.white))
            .fullScreenCover(isPresented: $showScripts) {
                ScriptsListView(userId: authService.user?.uid ?? "")
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Failed to sign out. Please try again.")
            }
        }
    }
}

#Preview {
    ContentView()
}
