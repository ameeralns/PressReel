import Foundation

// Represents the type of visual content needed for a scene
enum VisualType: String, Codable {
    case bRoll = "b-roll"       // Moving footage
    case staticImage = "static"  // Still image with Ken Burns effect
    case talking = "talking"     // Talking head or interview style
    case overlay = "overlay"     // Text or graphic overlay
}

// Represents a single scene in the video
struct VideoScene: Codable, Identifiable {
    let id = UUID()
    let startTime: Double       // Start time in seconds
    let duration: Double        // Duration in seconds
    let description: String     // Scene description
    let keywords: [String]      // Keywords for visual search
    let mood: String           // Emotional tone of the scene
    let visualType: VisualType // Type of visual content needed
    let transition: String?    // Transition to next scene
    
    var endTime: Double {
        startTime + duration
    }
    
    // For Firestore
    enum CodingKeys: String, CodingKey {
        case startTime, duration, description, keywords, mood, visualType, transition
    }
}

// Represents the complete analysis of a script for video creation
struct VideoAnalysis: Codable {
    let scenes: [VideoScene]
    let mainKeywords: [String]          // Overall video keywords
    let suggestedMusicMood: String      // Mood for background music
    let totalDuration: Double           // Should be between 25-35 seconds
    let contentTone: String             // Overall tone of the content
    let captionStyle: String           // Style for video captions
    
    var isValid: Bool {
        // Validate total duration is between 25-35 seconds
        let sceneDuration = scenes.reduce(0) { $0 + $1.duration }
        return (25...35).contains(sceneDuration)
    }
    
    // Helper to get keywords for Pixabay search
    var allKeywords: [String] {
        var keywords = Set(mainKeywords)
        scenes.forEach { scene in
            keywords.formUnion(scene.keywords)
        }
        return Array(keywords)
    }
    
    // Helper to validate scene continuity
    var hasValidSceneContinuity: Bool {
        var previousEndTime = 0.0
        return scenes.allSatisfy { scene in
            defer { previousEndTime = scene.endTime }
            return abs(scene.startTime - previousEndTime) < 0.1
        }
    }
    
    // Helper to validate scene durations
    var hasValidSceneDurations: Bool {
        scenes.allSatisfy { (2.0...8.0).contains($0.duration) }
    }
} 