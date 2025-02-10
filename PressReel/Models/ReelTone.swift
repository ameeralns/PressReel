import Foundation

enum ReelTone: String, Codable, CaseIterable {
    case professional
    case casual
    case dramatic
    
    var description: String {
        switch self {
        case .professional:
            return "Professional"
        case .casual:
            return "Casual"
        case .dramatic:
            return "Dramatic"
        }
    }
    
    var prompt: String {
        switch self {
        case .professional:
            return "professional and formal"
        case .casual:
            return "casual and conversational"
        case .dramatic:
            return "dramatic and engaging"
        }
    }
    
    var icon: String {
        switch self {
        case .professional: return "briefcase.fill"
        case .casual: return "person.fill"
        case .dramatic: return "theatermasks.fill"
        }
    }
} 