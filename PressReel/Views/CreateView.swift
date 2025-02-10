import SwiftUI
import PhotosUI
import Photos
import AVFoundation

struct CreateView: View {
    @Environment(\.dismiss) var dismiss
    @State private var showImportView = false
    @State private var showAiReelSheet = false
    
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
                GenerateAiReelSheet()
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

struct GenerateAiReelSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var script: String = ""
    @State private var selectedVoice: Voice = .allVoices[0]
    @State private var selectedTone: VideoTone = .professional
    @State private var isGenerating = false
    
    // Sample voices (to be replaced with Eleven Labs voices)
    struct Voice: Identifiable {
        let id: String
        let name: String
        let gender: String
        
        static let allVoices: [Voice] = [
            Voice(id: "v1", name: "Rachel", gender: "Female"),
            Voice(id: "v2", name: "James", gender: "Male"),
            Voice(id: "v3", name: "Emma", gender: "Female"),
            Voice(id: "v4", name: "Michael", gender: "Male")
        ]
    }
    
    enum VideoTone: String, CaseIterable {
        case professional = "Professional"
        case casual = "Casual"
        case dramatic = "Dramatic"
        
        var icon: String {
            switch self {
            case .professional: return "briefcase.fill"
            case .casual: return "person.fill"
            case .dramatic: return "theatermasks.fill"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color.black.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 30) {
                        // Header with Glow
                        ZStack {
                            // Glow Effect
                            Circle()
                                .fill(Color.red.opacity(0.3))
                                .frame(width: 100, height: 100)
                                .blur(radius: 20)
                            
                            Image(systemName: "wand.and.rays")
                                .font(.system(size: 40, weight: .semibold))
                                .foregroundColor(.red)
                                .symbolEffect(.bounce, options: .repeating)
                        }
                        .padding(.top, 20)
                        
                        // Script Input
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Your Script")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            TextEditor(text: $script)
                                .frame(height: 150)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.white.opacity(0.05))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .strokeBorder(
                                            LinearGradient(
                                                gradient: Gradient(colors: [.red.opacity(0.6), .red.opacity(0.2)]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal)
                        
                        // Voice Selection
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Choose Voice")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(Voice.allVoices) { voice in
                                        VStack {
                                            Circle()
                                                .fill(selectedVoice.id == voice.id ? Color.red : Color.white.opacity(0.05))
                                                .frame(width: 60, height: 60)
                                                .overlay(
                                                    Image(systemName: "waveform")
                                                        .foregroundColor(selectedVoice.id == voice.id ? .white : .red)
                                                )
                                            
                                            Text(voice.name)
                                                .font(.subheadline)
                                                .foregroundColor(.white)
                                            
                                            Text(voice.gender)
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.7))
                                        }
                                        .padding()
                                        .background(
                                            RoundedRectangle(cornerRadius: 16)
                                                .fill(Color.white.opacity(0.05))
                                        )
                                        .onTapGesture {
                                            selectedVoice = voice
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.horizontal)
                        
                        // Tone Selection
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Video Tone")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            HStack(spacing: 12) {
                                ForEach(VideoTone.allCases, id: \.self) { tone in
                                    VStack {
                                        Image(systemName: tone.icon)
                                            .font(.system(size: 24))
                                            .foregroundColor(selectedTone == tone ? .white : .red)
                                            .frame(width: 50, height: 50)
                                            .background(
                                                Circle()
                                                    .fill(selectedTone == tone ? Color.red : Color.white.opacity(0.05))
                                            )
                                        
                                        Text(tone.rawValue)
                                            .font(.subheadline)
                                            .foregroundColor(.white)
                                    }
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(Color.white.opacity(0.05))
                                    )
                                    .onTapGesture {
                                        selectedTone = tone
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.horizontal)
                        
                        // Generate Button
                        Button(action: {
                            isGenerating = true
                            // Generation logic will go here
                        }) {
                            HStack {
                                if isGenerating {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "wand.and.stars")
                                    Text("Generate Video")
                                }
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [.red, .red.opacity(0.8)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .cornerRadius(16)
                            .padding(.horizontal)
                        }
                        .disabled(script.isEmpty || isGenerating)
                        .opacity(script.isEmpty ? 0.5 : 1.0)
                    }
                    .padding(.bottom, 30)
                }
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
    }
}

#Preview {
    CreateView()
} 