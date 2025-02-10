import Foundation

enum ReelStatus: Codable, Equatable {
    case processing
    case analyzing
    case generatingVoiceover
    case gatheringVisuals
    case assemblingVideo
    case finalizing
    case completed
    case failed(error: String)
    case cancelled
    
    var description: String {
        switch self {
        case .processing:
            return "Processing"
        case .analyzing:
            return "Analyzing script..."
        case .generatingVoiceover:
            return "Generating voiceover..."
        case .gatheringVisuals:
            return "Gathering visuals..."
        case .assemblingVideo:
            return "Creating video..."
        case .finalizing:
            return "Finalizing..."
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
        case .processing:
            return 0.0
        case .analyzing:
            return 0.1
        case .generatingVoiceover:
            return 0.3
        case .gatheringVisuals:
            return 0.5
        case .assemblingVideo:
            return 0.7
        case .finalizing:
            return 0.9
        case .completed:
            return 1.0
        case .failed, .cancelled:
            return 0.0
        }
    }
} 