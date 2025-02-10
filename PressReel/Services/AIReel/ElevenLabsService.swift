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
    
    /// Generates voice audio for the entire script
    func generateVoiceover(script: String, voiceId: String, modelId: String = "eleven_multilingual_v2") async throws -> URL {
        let url = URL(string: "\(baseURL)/text-to-speech/\(voiceId)")!
        
        // Request body
        let body: [String: Any] = [
            "text": script,
            "model_id": modelId,
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.75,
                "style": 0.0,
                "use_speaker_boost": true
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.addValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ElevenLabsError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200:
            // Save audio file temporarily
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp3")
            
            try data.write(to: tempURL)
            return tempURL
            
        case 422:
            throw ElevenLabsError.invalidScript
        case 429:
            throw ElevenLabsError.rateLimitExceeded
        default:
            throw ElevenLabsError.requestFailed(statusCode: httpResponse.statusCode)
        }
    }
    
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
    
    /// Generates voice audio for a specific scene with timing markers
    func generateSceneVoiceover(scene: VideoScene, voiceId: String) async throws -> SceneAudio {
        let url = URL(string: "\(baseURL)/text-to-speech/\(voiceId)")!
        
        // Add SSML markers for timing
        let ssmlText = """
        <speak>
            <mark name="start"/>
            \(scene.description)
            <mark name="end"/>
        </speak>
        """
        
        let body: [String: Any] = [
            "text": ssmlText,
            "model_id": "eleven_multilingual_v2",
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.75,
                "style": 0.0,
                "use_speaker_boost": true
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.addValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ElevenLabsError.requestFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        // Save audio file temporarily
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp3")
        
        try data.write(to: tempURL)
        
        return SceneAudio(
            audioURL: tempURL,
            startTime: scene.startTime,
            duration: scene.duration
        )
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

struct SceneAudio {
    let audioURL: URL      // Local URL to the audio file
    let startTime: Double  // When this audio should start in the final video
    let duration: Double   // Duration of the audio clip
}

// MARK: - Errors
enum ElevenLabsError: LocalizedError {
    case invalidResponse
    case requestFailed(statusCode: Int)
    case invalidScript
    case rateLimitExceeded
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from ElevenLabs"
        case .requestFailed(let statusCode):
            return "Request failed with status code: \(statusCode)"
        case .invalidScript:
            return "Invalid script format"
        case .rateLimitExceeded:
            return "Rate limit exceeded"
        }
    }
} 