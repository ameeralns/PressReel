import SwiftUI
import AVFoundation

struct GenerateAiReelSheet: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel: AiReelViewModel
    @State private var script: String = ""
    @State private var selectedTone: ReelTone = .professional
    @State private var isGenerating = false
    @State private var audioPlayer: AVPlayer?
    @State private var isPlayingPreview = false
    
    init(userId: String) {
        _viewModel = StateObject(wrappedValue: AiReelViewModel(userId: userId))
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
                                    ForEach(viewModel.availableVoices, id: \.voiceId) { voice in
                                        VStack {
                                            // Voice Circle with Play/Pause
                                            Circle()
                                                .fill(viewModel.selectedVoiceId == voice.voiceId ? Color.red : Color.white.opacity(0.05))
                                                .frame(width: 60, height: 60)
                                                .overlay(
                                                    Image(systemName: isPlayingPreview && viewModel.selectedVoiceId == voice.voiceId ? "pause.fill" : "play.fill")
                                                        .foregroundColor(viewModel.selectedVoiceId == voice.voiceId ? .white : .red)
                                                )
                                                .onTapGesture {
                                                    // Select the voice
                                                    viewModel.selectedVoiceId = voice.voiceId
                                                    
                                                    // Handle preview playback
                                                    if isPlayingPreview {
                                                        audioPlayer?.pause()
                                                        isPlayingPreview = false
                                                    } else {
                                                        playPreview(for: voice)
                                                    }
                                                }
                                            
                                            Text(voice.name)
                                                .font(.subheadline)
                                                .foregroundColor(.white)
                                            
                                            Text(voice.category ?? "General")
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.7))
                                        }
                                        .padding()
                                        .background(
                                            RoundedRectangle(cornerRadius: 16)
                                                .fill(Color.white.opacity(0.05))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .strokeBorder(
                                                    viewModel.selectedVoiceId == voice.voiceId ? 
                                                        Color.red : Color.clear,
                                                    lineWidth: 2
                                                )
                                        )
                                        .onTapGesture {
                                            viewModel.selectedVoiceId = voice.voiceId
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
                                ForEach(ReelTone.allCases, id: \.self) { tone in
                                    VStack {
                                        Image(systemName: tone.icon)
                                            .font(.system(size: 24))
                                            .foregroundColor(selectedTone == tone ? .white : .red)
                                            .frame(width: 50, height: 50)
                                            .background(
                                                Circle()
                                                    .fill(selectedTone == tone ? Color.red : Color.white.opacity(0.05))
                                            )
                                        
                                        Text(tone.description)
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
                            Task {
                                do {
                                    try await viewModel.createReel(script: script)
                                    dismiss()
                                } catch {
                                    // Handle error
                                    isGenerating = false
                                }
                            }
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
        .onDisappear {
            audioPlayer?.pause()
            audioPlayer = nil
            NotificationCenter.default.removeObserver(self)
        }
    }
    
    private func playPreview(for voice: Voice) {
        // Stop any existing preview
        audioPlayer?.pause()
        
        // Create new player with preview URL
        let player = AVPlayer(url: voice.previewURL)
        audioPlayer = player
        isPlayingPreview = true
        
        // Set up audio session
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        
        // Play preview
        player.play()
        
        // Add completion handler
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            isPlayingPreview = false
            audioPlayer = nil
        }
    }
} 