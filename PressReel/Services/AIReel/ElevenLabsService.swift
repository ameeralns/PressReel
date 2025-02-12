import Foundation

actor ElevenLabsService {
    // MARK: - Properties
    private let apiKey: String
    private let baseURL = "https://api.elevenlabs.io/v1"
    
    // MARK: - Initialization
    init() {
        guard let apiKey = Bundle.main.infoDictionary?["ELEVENLABS_API_KEY"] as? String else {
            fatalError("ElevenLabs API Key not found in configuration")
        }
        self.apiKey = apiKey
    }
    
    // MARK: - Public Methods
    /// Fetches available voices
    func fetchVoices() async throws -> [Voice] {
        let url = URL(string: "\(baseURL)/voices")!
        
        var request = URLRequest(url: url)
        request.addValue(apiKey, forHTTPHeaderField: "xi-api-key")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ElevenLabsError.requestFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        let voicesResponse = try JSONDecoder().decode(VoicesResponse.self, from: data)
        return voicesResponse.voices
    }
}

// MARK: - Models
struct Voice: Codable {
    let voiceId: String
    let name: String
    let previewURL: URL
    let category: String?
    let labels: [String: String]
    
    enum CodingKeys: String, CodingKey {
        case voiceId = "voice_id"
        case name
        case previewURL = "preview_url"
        case category
        case labels
    }
}

struct VoicesResponse: Codable {
    let voices: [Voice]
}

// MARK: - Errors
enum ElevenLabsError: LocalizedError {
    case requestFailed(statusCode: Int)
    
    var errorDescription: String? {
        switch self {
        case .requestFailed(let statusCode):
            return "Request failed with status code: \(statusCode)"
        }
    }
} 