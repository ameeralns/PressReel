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
            print("📢 Loaded \(availableVoices.count) voices")
            // Set default voice if none selected
            if selectedVoiceId == nil {
                selectedVoiceId = availableVoices.first?.voiceId
                print("📢 Set default voice ID: \(selectedVoiceId ?? "none")")
            }
        } catch {
            print("❌ Error loading voices: \(error)")
            self.error = error
        }
        isLoading = false
    }
    
    // MARK: - Reel Creation
    func createReel(script: String) async throws -> String {
        guard let voiceId = selectedVoiceId else {
            print("❌ No voice selected")
            throw AiReelError.noVoiceSelected
        }
        
        print("📢 Creating reel with voice ID: \(voiceId)")
        print("📢 Using userId: \(userId)")
        print("📢 Current auth state: \(Auth.auth().currentUser?.uid ?? "Not authenticated")")
        
        isLoading = true
        defer { isLoading = false }
        
        // Verify authentication
        guard let currentUser = Auth.auth().currentUser else {
            print("❌ User not authenticated")
            throw AiReelError.notAuthenticated
        }
        
        do {
            // First create the script document
            let scriptId = UUID().uuidString
            let scriptData: [String: Any] = [
                "id": scriptId,
                "userId": currentUser.uid,
                "content": script,
                "createdAt": Timestamp(date: Date()),
                "title": "AI Reel Script"
            ]
            
            print("📢 Attempting to save script with data: \(scriptData)")
            
            // Save script document
            try await db.collection("scripts").document(scriptId).setData(scriptData)
            print("✅ Script document saved successfully")
            
            // Create reel document with all required fields
            let reel = AiReel(
                scriptId: scriptId,
                voiceId: voiceId,
                tone: selectedTone,
                userId: currentUser.uid
            )
            
            // Create the reel data dictionary
            let reelData: [String: Any] = [
                "scriptId": reel.scriptId,
                "status": reel.status.description.lowercased(),
                "progress": reel.progress,
                "createdAt": Timestamp(date: reel.createdAt),
                "updatedAt": Timestamp(date: reel.updatedAt),
                "voiceId": reel.voiceId,
                "tone": reel.tone.rawValue,
                "userId": reel.userId,
                "videoURL": reel.videoURL as Any,
                "thumbnailURL": reel.thumbnailURL as Any
            ]
            
            print("📢 Creating AiReel with data: \(reelData)")
            
            // Create a new document reference with auto-generated ID
            let reelRef = db.collection("aiReels").document()
            try await reelRef.setData(reelData)
            print("✅ Reel document saved successfully with ID: \(reelRef.documentID)")
            
            // Start listening for updates on this specific reel
            currentReel = reel
            
            return reelRef.documentID
        } catch {
            print("❌ Error creating reel: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - Private Methods
    private func setupReelsListener() {
        reelsListener?.remove()
        
        let query = db.collection("aiReels")
            .whereField("userId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: 10) // Limit to most recent 10 reels for better performance
        
        reelsListener = query.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ Error listening to reels: \(error.localizedDescription)")
                self.error = error
                return
            }
            
            guard let documents = snapshot?.documents else {
                print("⚠️ No documents in snapshot")
                return
            }
            
            print("📢 Received \(documents.count) reel updates")
            self.reels = documents.compactMap { document in
                do {
                    var reel = try document.data(as: AiReel.self)
                    reel.id = document.documentID // Ensure ID is set
                    return reel
                } catch {
                    print("❌ Error decoding reel: \(error.localizedDescription)")
                    return nil
                }
            }
        }
    }
    
    func cancelReel(_ reel: AiReel) async throws {
        guard let reelId = reel.id else {
            print("❌ Cannot cancel reel: missing ID")
            throw AiReelError.invalidReel
        }
        
        print("📢 Cancelling reel: \(reelId)")
        try await db.collection("aiReels").document(reelId).updateData([
            "status": "cancelled",
            "updatedAt": Timestamp(date: Date())
        ])
        print("✅ Reel cancelled successfully")
    }
    
    func deleteReel(_ reel: AiReel) async throws {
        guard let reelId = reel.id else {
            print("❌ Cannot delete reel: missing ID")
            throw AiReelError.invalidReel
        }
        
        print("📢 Deleting reel: \(reelId)")
        try await db.collection("aiReels").document(reelId).delete()
        print("✅ Reel deleted successfully")
    }
}

// MARK: - Errors
enum AiReelError: LocalizedError {
    case noVoiceSelected
    case notAuthenticated
    case invalidReel
    
    var errorDescription: String? {
        switch self {
        case .noVoiceSelected:
            return "Please select a voice before creating the reel"
        case .notAuthenticated:
            return "User not authenticated"
        case .invalidReel:
            return "Invalid reel: missing ID"
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