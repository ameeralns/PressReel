import SwiftUI
import FirebaseFirestore

struct ReelProgressView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel: ReelProgressViewModel
    @State private var showSuccessAnimation = false
    @State private var successScale: CGFloat = 0.5
    @State private var rotationAngle: Double = 0
    
    init(reelId: String) {
        _viewModel = StateObject(wrappedValue: ReelProgressViewModel(reelId: reelId))
    }
    
    var body: some View {
        ZStack {
            // Animated Background
            Color.black
                .overlay(
                    ZStack {
                        // Animated gradient circles
                        Circle()
                            .fill(Color.red.opacity(0.1))
                            .frame(width: 300, height: 300)
                            .blur(radius: 30)
                            .offset(y: -100)
                        
                        Circle()
                            .fill(Color.red.opacity(0.1))
                            .frame(width: 200, height: 200)
                            .blur(radius: 20)
                            .offset(x: 150, y: 150)
                            .rotationEffect(.degrees(rotationAngle))
                    }
                )
                .ignoresSafeArea()
            
            if showSuccessAnimation && viewModel.isCompleted {
                // Success Animation
                VStack(spacing: 30) {
                    SuccessCheckmark()
                        .frame(width: 200, height: 200)
                        .scaleEffect(successScale)
                    
                    Text("Video Generated!")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .opacity(successScale)
                    
                    Text("Your video is ready to share")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.8))
                        .opacity(successScale)
                    
                    Button(action: { dismiss() }) {
                        Text("Done")
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
                    .opacity(successScale)
                }
                .transition(.opacity)
            } else {
                // Main Progress View
                VStack(spacing: 40) {
                    // Header with Animation
                    ZStack {
                        // Glow Effect
                        Circle()
                            .fill(Color.red.opacity(0.3))
                            .frame(width: 120, height: 120)
                            .blur(radius: 20)
                        
                        // Icon with rotation
                        Image(systemName: viewModel.currentIcon)
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundColor(.red)
                            .symbolEffect(.bounce, options: .repeating)
                            .rotationEffect(.degrees(rotationAngle))
                    }
                    .padding(.top, 40)
                    
                    // Status Text with Gradient
                    Text(viewModel.currentStatus.description)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .animation(.easeInOut, value: viewModel.currentStatus)
                    
                    // Progress Circle with Glow
                    ZStack {
                        // Glow Effect
                        Circle()
                            .stroke(Color.red.opacity(0.3), lineWidth: 8)
                            .frame(width: 220, height: 220)
                            .blur(radius: 10)
                        
                        // Background Circle
                        Circle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 8)
                            .frame(width: 200, height: 200)
                        
                        // Progress Circle
                        Circle()
                            .trim(from: 0, to: viewModel.progress)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [.red, .red.opacity(0.8)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round)
                            )
                            .frame(width: 200, height: 200)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut, value: viewModel.progress)
                        
                        // Percentage Text with Shadow
                        Text("\(Int(viewModel.progress * 100))%")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundColor(.white)
                            .shadow(color: .red.opacity(0.3), radius: 10, x: 0, y: 0)
                    }
                    
                    // Status Steps with Modern Style
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(ReelStatus.allCases, id: \.description) { status in
                            if case .failed(_) = status {} else {
                                HStack(spacing: 15) {
                                    // Step Circle with Glow
                                    Circle()
                                        .fill(status == viewModel.currentStatus ? Color.red : Color.white.opacity(0.1))
                                        .frame(width: 30, height: 30)
                                        .shadow(color: status == viewModel.currentStatus ? .red.opacity(0.5) : .clear, radius: 5)
                                        .overlay(
                                            Image(systemName: status == viewModel.currentStatus ? "arrow.right" : 
                                                (status.progress < viewModel.currentStatus.progress ? "checkmark" : ""))
                                                .foregroundColor(.white)
                                        )
                                    
                                    // Step Text with Gradient
                                    Text(status.description)
                                        .font(.body)
                                        .foregroundStyle(
                                            status == viewModel.currentStatus ?
                                                LinearGradient(colors: [.white, .white.opacity(0.8)], startPoint: .leading, endPoint: .trailing) :
                                                LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0.4)], startPoint: .leading, endPoint: .trailing)
                                        )
                                }
                                .animation(.easeInOut, value: viewModel.currentStatus)
                            }
                        }
                    }
                    .padding(.horizontal, 40)
                    
                    Spacer()
                    
                    // Cancel Button with Gradient Border
                    if !viewModel.isCompleted {
                        Button(action: {
                            Task {
                                await viewModel.cancelReel()
                                dismiss()
                            }
                        }) {
                            Text("Cancel")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(Color.red.opacity(0.2))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .strokeBorder(
                                            LinearGradient(
                                                colors: [.red.opacity(0.6), .red.opacity(0.2)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                                .cornerRadius(16)
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 30)
                    }
                }
            }
        }
        .onAppear {
            // Start background animation
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
        }
        .onChange(of: viewModel.isCompleted) { completed in
            if completed {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    showSuccessAnimation = true
                    successScale = 1.0
                }
                // Dismiss after animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    dismiss()
                }
            }
        }
    }
}

class ReelProgressViewModel: ObservableObject {
    @Published var currentStatus: ReelStatus = .processing
    @Published var progress: Double = 0.0
    @Published var isCompleted = false
    private var listener: ListenerRegistration?
    private let reelId: String
    private let db = Firestore.firestore()
    
    var currentIcon: String {
        switch currentStatus {
        case .processing: return "gear"
        case .analyzing: return "doc.text.magnifyingglass"
        case .generatingVoiceover: return "waveform"
        case .gatheringVisuals: return "photo.stack"
        case .assemblingVideo: return "film"
        case .finalizing: return "checkmark.circle"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle"
        case .cancelled: return "xmark.circle"
        }
    }
    
    init(reelId: String) {
        self.reelId = reelId
        setupListener()
    }
    
    deinit {
        listener?.remove()
    }
    
    private func setupListener() {
        listener = db.collection("aiReels").document(reelId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self,
                      let data = snapshot?.data(),
                      let status = data["status"] as? String else { return }
                
                DispatchQueue.main.async {
                    self.progress = data["progress"] as? Double ?? 0.0
                    
                    switch status {
                    case "processing": self.currentStatus = .processing
                    case "analyzing": self.currentStatus = .analyzing
                    case "generatingVoiceover": self.currentStatus = .generatingVoiceover
                    case "gatheringVisuals": self.currentStatus = .gatheringVisuals
                    case "assemblingVideo": self.currentStatus = .assemblingVideo
                    case "finalizing": self.currentStatus = .finalizing
                    case "completed":
                        self.currentStatus = .completed
                        self.progress = 1.0
                        self.isCompleted = true
                    case "failed":
                        if let error = data["error"] as? String {
                            self.currentStatus = .failed(error: error)
                        }
                    case "cancelled": self.currentStatus = .cancelled
                    default: break
                    }
                }
            }
    }
    
    func cancelReel() async {
        do {
            try await db.collection("aiReels").document(reelId).updateData([
                "status": "cancelled",
                "updatedAt": Timestamp(date: Date())
            ])
        } catch {
            print("Error cancelling reel: \(error)")
        }
    }
} 