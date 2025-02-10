import SwiftUI
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth

@MainActor
class AiReelViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var reels: [AiReel] = []
    @Published var availableVoices: [Voice] = []
    @Published var selectedVoiceId: String?
    @Published var selectedTone: ReelTone = .professional
    @Published var isLoading = false
    @Published var error: Error?
    @Published var currentReel: AiReel?
    
    // MARK: - Private Properties
    private let db = Firestore.firestore()
    private let elevenLabsService = ElevenLabsService()
    private var reelsListener: ListenerRegistration?
    let userId: String
    
    // MARK: - Initialization
    init(userId: String) {
        self.userId = userId
        setupReelsListener()
        Task {
            await loadVoices()
        }
    }
    
    deinit {
        reelsListener?.remove()
    }
    
    // MARK: - Voice Management
    private func loadVoices() async {
        do {
            isLoading = true
            availableVoices = try await elevenLabsService.fetchVoices()
            // Set default voice if none selected
            if selectedVoiceId == nil {
                selectedVoiceId = availableVoices.first?.voiceId
            }
        } catch {
            self.error = error
        }
        isLoading = false
    }
    
    // MARK: - Reel Creation
    func createReel(script: String) async throws {
        guard let voiceId = selectedVoiceId else {
            throw AiReelError.noVoiceSelected
        }
        
        isLoading = true
        defer { isLoading = false }
        
        // Create initial reel document
        let reel = AiReel(
            scriptId: script,
            voiceId: voiceId,
            tone: selectedTone,
            userId: userId
        )
        
        // Save to Firestore (this will trigger the Cloud Function)
        try await db.collection("aiReels").document().setData(reel.dictionary)
    }
    
    func cancelReel(_ reel: AiReel) async throws {
        guard let reelId = reel.id else { return }
        try await db.collection("aiReels").document(reelId).updateData([
            "status": ReelStatus.cancelled,
            "updatedAt": Timestamp(date: Date())
        ])
    }
    
    func deleteReel(_ reel: AiReel) async throws {
        guard let reelId = reel.id else { return }
        try await db.collection("aiReels").document(reelId).delete()
    }
    
    // MARK: - Private Methods
    private func setupReelsListener() {
        reelsListener?.remove()
        
        let query = db.collection("aiReels")
            .whereField("userId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
        
        reelsListener = query.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                self.error = error
                return
            }
            
            guard let documents = snapshot?.documents else { return }
            
            self.reels = documents.compactMap { document in
                try? document.data(as: AiReel.self)
            }
        }
    }
}

// MARK: - Errors
enum AiReelError: LocalizedError {
    case noVoiceSelected
    
    var errorDescription: String? {
        switch self {
        case .noVoiceSelected:
            return "Please select a voice before creating the reel"
        }
    }
}

// MARK: - Helpers
private extension AiReel {
    var dictionary: [String: Any] {
        [
            "scriptId": scriptId,
            "status": status,
            "progress": progress,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt),
            "voiceId": voiceId,
            "tone": tone.rawValue,
            "userId": userId,
            "videoURL": videoURL as Any,
            "thumbnailURL": thumbnailURL as Any
        ]
    }
} 