import Foundation

enum ReelStatus: Hashable, CaseIterable, Codable {
    case processing
    case analyzing
    case generatingVoiceover
    case gatheringVisuals
    case assemblingVideo
    case finalizing
    case completed
    case failed(error: String)
    case cancelled
    
    static var allCases: [ReelStatus] {
        [
            .processing,
            .analyzing,
            .generatingVoiceover,
            .gatheringVisuals,
            .assemblingVideo,
            .finalizing,
            .completed,
            .cancelled
        ]
    }
    
    var description: String {
        switch self {
        case .processing:
            return "Processing"
        case .analyzing:
            return "Analyzing Script"
        case .generatingVoiceover:
            return "Generating Voiceover"
        case .gatheringVisuals:
            return "Gathering Visuals"
        case .assemblingVideo:
            return "Assembling Video"
        case .finalizing:
            return "Finalizing"
        case .completed:
            return "Completed"
        case .failed(let error):
            return "Failed: \(error)"
        case .cancelled:
            return "Cancelled"
        }
    }
    
    var progress: Double {
        switch self {
        case .processing: return 0.0
        case .analyzing: return 0.2
        case .generatingVoiceover: return 0.4
        case .gatheringVisuals: return 0.6
        case .assemblingVideo: return 0.8
        case .finalizing: return 0.9
        case .completed: return 1.0
        case .failed: return 0.0
        case .cancelled: return 0.0
        }
    }
    
    func hash(into hasher: inout Hasher) {
        switch self {
        case .processing:
            hasher.combine(0)
        case .analyzing:
            hasher.combine(1)
        case .generatingVoiceover:
            hasher.combine(2)
        case .gatheringVisuals:
            hasher.combine(3)
        case .assemblingVideo:
            hasher.combine(4)
        case .finalizing:
            hasher.combine(5)
        case .completed:
            hasher.combine(6)
        case .failed(let error):
            hasher.combine(7)
            hasher.combine(error)
        case .cancelled:
            hasher.combine(8)
        }
    }
    
    static func == (lhs: ReelStatus, rhs: ReelStatus) -> Bool {
        switch (lhs, rhs) {
        case (.processing, .processing),
             (.analyzing, .analyzing),
             (.generatingVoiceover, .generatingVoiceover),
             (.gatheringVisuals, .gatheringVisuals),
             (.assemblingVideo, .assemblingVideo),
             (.finalizing, .finalizing),
             (.completed, .completed),
             (.cancelled, .cancelled):
            return true
        case (.failed(let error1), .failed(let error2)):
            return error1 == error2
        default:
            return false
        }
    }
    
    // Custom Codable implementation for handling associated values
    private enum CodingKeys: String, CodingKey {
        case status
        case error
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let status = try container.decode(String.self, forKey: .status)
        
        switch status.lowercased() {
        case "processing": self = .processing
        case "analyzing": self = .analyzing
        case "generatingvoiceover": self = .generatingVoiceover
        case "gatheringvisuals": self = .gatheringVisuals
        case "assemblingvideo": self = .assemblingVideo
        case "finalizing": self = .finalizing
        case "completed": self = .completed
        case "cancelled": self = .cancelled
        case "failed":
            let error = try container.decode(String.self, forKey: .error)
            self = .failed(error: error)
        default:
            throw DecodingError.dataCorruptedError(forKey: .status, in: container, debugDescription: "Invalid status: \(status)")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .processing:
            try container.encode("processing", forKey: .status)
        case .analyzing:
            try container.encode("analyzing", forKey: .status)
        case .generatingVoiceover:
            try container.encode("generatingvoiceover", forKey: .status)
        case .gatheringVisuals:
            try container.encode("gatheringvisuals", forKey: .status)
        case .assemblingVideo:
            try container.encode("assemblingvideo", forKey: .status)
        case .finalizing:
            try container.encode("finalizing", forKey: .status)
        case .completed:
            try container.encode("completed", forKey: .status)
        case .cancelled:
            try container.encode("cancelled", forKey: .status)
        case .failed(let error):
            try container.encode("failed", forKey: .status)
            try container.encode(error, forKey: .error)
        }
    }
} 