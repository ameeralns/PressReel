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
        print("📢 Initializing AiReel with voice ID: \(voiceId)")
        self.scriptId = scriptId
        self.status = .processing
        self.progress = 0.0
        self.createdAt = Date()
        self.updatedAt = Date()
        self.voiceId = voiceId
        self.tone = tone
        self.userId = userId
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case scriptId
        case status
        case progress
        case createdAt
        case updatedAt
        case videoURL
        case thumbnailURL
        case voiceId
        case tone
        case userId
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        scriptId = try container.decode(String.self, forKey: .scriptId)
        status = try container.decode(ReelStatus.self, forKey: .status)
        progress = try container.decode(Double.self, forKey: .progress)
        
        // Handle Timestamp to Date conversion
        if let timestamp = try? container.decode(Timestamp.self, forKey: .createdAt) {
            createdAt = timestamp.dateValue()
        } else {
            createdAt = try container.decode(Date.self, forKey: .createdAt)
        }
        
        if let timestamp = try? container.decode(Timestamp.self, forKey: .updatedAt) {
            updatedAt = timestamp.dateValue()
        } else {
            updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        }
        
        videoURL = try container.decodeIfPresent(String.self, forKey: .videoURL)
        thumbnailURL = try container.decodeIfPresent(String.self, forKey: .thumbnailURL)
        voiceId = try container.decode(String.self, forKey: .voiceId)
        tone = try container.decode(ReelTone.self, forKey: .tone)
        userId = try container.decode(String.self, forKey: .userId)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(scriptId, forKey: .scriptId)
        try container.encode(status, forKey: .status)
        try container.encode(progress, forKey: .progress)
        try container.encode(Timestamp(date: createdAt), forKey: .createdAt)
        try container.encode(Timestamp(date: updatedAt), forKey: .updatedAt)
        try container.encodeIfPresent(videoURL, forKey: .videoURL)
        try container.encodeIfPresent(thumbnailURL, forKey: .thumbnailURL)
        try container.encode(voiceId, forKey: .voiceId)
        try container.encode(tone, forKey: .tone)
        try container.encode(userId, forKey: .userId)
    }
    
    // Helper method to convert status string from Firestore to ReelStatus enum
    static func statusFromString(_ status: String) -> ReelStatus {
        switch status.lowercased() {
        case "processing": return .processing
        case "analyzing": return .analyzing
        case "generatingvoiceover": return .generatingVoiceover
        case "gatheringvisuals": return .gatheringVisuals
        case "assemblingvideo": return .assemblingVideo
        case "finalizing": return .finalizing
        case "completed": return .completed
        case "cancelled": return .cancelled
        case let s where s.starts(with: "failed:"): 
            let error = String(s.dropFirst(7))
            return .failed(error: error)
        default: return .processing
        }
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
