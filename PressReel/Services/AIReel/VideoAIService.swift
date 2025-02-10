import Foundation

actor VideoAIService {
    // MARK: - Properties
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    
    // MARK: - Initialization
    init() {
        guard let apiKey = Bundle.main.infoDictionary?["OPENAI_API_KEY"] as? String else {
            fatalError("OpenAI API Key not found in configuration")
        }
        self.apiKey = apiKey
    }
    
    // MARK: - Public Methods
    func analyzeScript(_ script: String, tone: ReelTone) async throws -> VideoAnalysis {
        let requestBody: [String: Any] = [
            "model": "gpt-4-turbo-preview",
            "messages": [
                [
                    "role": "system",
                    "content": createSystemPrompt()
                ],
                [
                    "role": "user",
                    "content": createAnalysisPrompt(script: script, tone: tone)
                ]
            ],
            "response_format": ["type": "json_object"],
            "temperature": 0.8 // Increased for more creative variations
        ]
        
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw VideoAIError.requestFailed
        }
        
        struct OpenAIResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }
        
        let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let jsonString = openAIResponse.choices.first?.message.content else {
            throw VideoAIError.invalidResponse
        }
        
        return try parseResponse(jsonString)
    }
    
    // MARK: - Private Methods
    private func createSystemPrompt() -> String {
        """
        You are a creative video director and editor specializing in creating engaging, dynamic video reels.
        Your task is to analyze scripts and break them down into impactful scenes that capture attention and tell a compelling story.
        
        Key requirements:
        1. Create a dynamic number of scenes based on the content and narrative flow
        2. Each scene should be as long as needed to convey its message effectively
        3. Focus on creating engaging visual transitions and maintaining viewer interest
        4. Generate specific, detailed keywords for stock footage search
        5. Total duration should be between 25-35 seconds, optimized for the content
        6. Scene length should vary based on content importance and visual impact
        
        The goal is to create videos that are:
        - Engaging from start to finish
        - Visually diverse and interesting
        - Well-paced for the content
        - Natural in their flow
        - Optimized for social media sharing
        
        Provide detailed scene descriptions, precise keywords for visual search, and creative transition suggestions.
        """
    }
    
    private func createAnalysisPrompt(script: String, tone: ReelTone) -> String {
        """
        Create an engaging video reel from this script. The tone should be \(tone.prompt).
        
        Script:
        \(script)
        
        Break this down into scenes that best tell the story. For each scene, provide:
        1. Scene Details:
           - Start time and duration (in seconds)
           - Vivid description of what should be shown
           - Specific keywords for visual search
           - Emotional mood/impact
           - Visual type (b-roll, static, talking, overlay)
           - Transition suggestion to next scene
        
        2. Additional Elements:
           - Main video keywords
           - Music mood and style
           - Overall emotional journey
           - Caption style suggestions
        
        Respond in the following JSON format:
        {
            "scenes": [
                {
                    "startTime": 0,
                    "duration": 3.5,
                    "description": "Close-up of advanced medical robot performing precision surgery",
                    "keywords": ["medical robot", "surgical precision", "healthcare technology"],
                    "mood": "innovative and precise",
                    "visualType": "b-roll",
                    "transition": "fade through white"
                }
            ],
            "mainKeywords": ["healthcare", "innovation", "future"],
            "suggestedMusicMood": "inspiring electronic",
            "totalDuration": 28.5,
            "contentTone": "professional yet engaging",
            "captionStyle": "modern, minimalist, appearing with smooth fade"
        }
        
        Guidelines:
        1. Create as many scenes as needed to tell the story effectively
        2. Vary scene lengths based on content importance (2-8 seconds per scene)
        3. Total duration should feel natural (25-35 seconds)
        4. Each scene should have a clear purpose and impact
        5. Consider attention span and engagement throughout
        """
    }
    
    private func parseResponse(_ jsonString: String) throws -> VideoAnalysis {
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw VideoAIError.parsingFailed
        }
        
        let decoder = JSONDecoder()
        let analysis = try decoder.decode(VideoAnalysis.self, from: jsonData)
        
        // Validate duration is within acceptable range
        guard (25...35).contains(analysis.totalDuration) else {
            throw VideoAIError.invalidDuration
        }
        
        return analysis
    }
}

// MARK: - Errors
enum VideoAIError: LocalizedError {
    case requestFailed
    case invalidResponse
    case parsingFailed
    case invalidDuration
    
    var errorDescription: String? {
        switch self {
        case .requestFailed:
            return "Failed to make request to OpenAI"
        case .invalidResponse:
            return "Received invalid response from OpenAI"
        case .parsingFailed:
            return "Failed to parse OpenAI response"
        case .invalidDuration:
            return "Video duration must be between 25 and 35 seconds"
        }
    }
} 