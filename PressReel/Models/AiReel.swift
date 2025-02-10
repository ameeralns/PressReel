import Foundation
import FirebaseFirestore

struct AiReel: Identifiable, Codable {
    @DocumentID var id: String?
    let scriptId: String
    var status: ReelStatus
    var progress: Double
    let createdAt: Date
    var updatedAt: Date
    var videoURL: String?
    var thumbnailURL: String?
    let voiceId: String
    let tone: ReelTone
    let userId: String
    
    var isProcessing: Bool {
        switch status {
        case .completed, .failed, .cancelled:
            return false
        default:
            return true
        }
    }
    
    init(scriptId: String, voiceId: String, tone: ReelTone, userId: String) {
        self.scriptId = scriptId
        self.status = .processing
        self.progress = 0.0
        self.createdAt = Date()
        self.updatedAt = Date()
        self.voiceId = voiceId
        self.tone = tone
        self.userId = userId
    }
}

// MARK: - Mock Data
extension AiReel {
    static var mockProcessing: AiReel {
        AiReel(scriptId: "mock-script-1",
               voiceId: "mock-voice-1",
               tone: .professional,
               userId: "mock-user-1")
    }
    
    static var mockCompleted: AiReel {
        var reel = AiReel(scriptId: "mock-script-2",
                         voiceId: "mock-voice-2",
                         tone: .casual,
                         userId: "mock-user-1")
        reel.status = .completed
        reel.progress = 1.0
        reel.videoURL = "https://example.com/mock-video.mp4"
        reel.thumbnailURL = "https://example.com/mock-thumbnail.jpg"
        return reel
    }
} 
