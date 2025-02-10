import SwiftUI
import PhotosUI
import Photos
import AVFoundation

struct CreateView: View {
    @Environment(\.dismiss) var dismiss
    @State private var showImportView = false
    @State private var showAiReelSheet = false
    let userId: String
    
    init(userId: String = "") {
        self.userId = userId
    }
    
    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // Enhanced Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Create")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text("Choose how you want to create your next video")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 16)
                    
                    // Create Buttons Container
                    VStack(spacing: 20) {
                        // Manual Project Button
                        Button(action: {
                            showImportView = true
                        }) {
                            VStack(spacing: 24) {
                                // Icon
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 64, weight: .semibold))
                                    .foregroundColor(.red)
                                    .frame(width: 120, height: 120)
                                    .background(Color.white.opacity(0.1))
                                    .clipShape(Circle())
                                
                                // Text Content
                                VStack(spacing: 12) {
                                    Text("Create Project")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                    
                                    Text("Import videos from your camera roll")
                                        .font(.body)
                                        .foregroundColor(.white.opacity(0.7))
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 24)
                                        .lineLimit(2)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 320)
                            .background(
                                RoundedRectangle(cornerRadius: 24)
                                    .fill(Color.white.opacity(0.05))
                            )
                        }
                        
                        // AI Reel Button
                        Button(action: {
                            showAiReelSheet = true
                        }) {
                            VStack(spacing: 24) {
                                // Icon Container with Glow
                                ZStack {
                                    // Glow Effect
                                    Circle()
                                        .fill(Color.red.opacity(0.3))
                                        .frame(width: 140, height: 140)
                                        .blur(radius: 20)
                                    
                                    // Icon Background
                                    Circle()
                                        .fill(LinearGradient(
                                            gradient: Gradient(colors: [Color.red.opacity(0.2), Color.black]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ))
                                        .frame(width: 120, height: 120)
                                    
                                    // Icon
                                    Image(systemName: "wand.and.rays")
                                        .font(.system(size: 64, weight: .semibold))
                                        .foregroundColor(.red)
                                        .symbolEffect(.bounce, options: .repeating)
                                }
                                
                                // Text Content
                                VStack(spacing: 12) {
                                    Text("AI Reel")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                    
                                    Text("Generate video from your script")
                                        .font(.body)
                                        .foregroundColor(.white.opacity(0.7))
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 24)
                                        .lineLimit(2)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 320)
                            .background(
                                RoundedRectangle(cornerRadius: 24)
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color.white.opacity(0.1),
                                                Color.red.opacity(0.05)
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 24)
                                    .strokeBorder(
                                        LinearGradient(
                                            gradient: Gradient(colors: [.red.opacity(0.6), .red.opacity(0.2)]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 100) // Add padding for tab bar
            }
            .background(Color.black.edgesIgnoringSafeArea(.all))
            .fullScreenCover(isPresented: $showImportView) {
                ImportVideosView()
            }
            .sheet(isPresented: $showAiReelSheet) {
                GenerateAiReelSheet(userId: userId)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

#Preview {
    CreateView()
} 