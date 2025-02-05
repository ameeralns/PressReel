import Foundation

class OpenAIService {
    private var apiKey: String {
        // Multiple methods to retrieve the API key
        let retrievalMethods: [() -> String?] = [
            // 1. Try environment variable
            { ProcessInfo.processInfo.environment["OPENAI_API_KEY"] },
            
            // 2. Try Info.plist
            { Bundle.main.infoDictionary?["OPENAI_API_KEY"] as? String },
            
            // 3. Try reading from Config.xcconfig directly
            { 
                guard let configPath = Bundle.main.path(forResource: "Config", ofType: "xcconfig") else { return nil }
                do {
                    let configContent = try String(contentsOfFile: configPath)
                    let lines = configContent.components(separatedBy: .newlines)
                    for line in lines {
                        if line.contains("OPENAI_API_KEY") {
                            return line.components(separatedBy: "=").last?.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                } catch {
                    print("Error reading Config.xcconfig: \(error)")
                }
                return nil
            }
        ]
        
        // Attempt to retrieve API key
        for method in retrievalMethods {
            if let key = method(), 
               !key.isEmpty, 
               !key.contains("$(OPENAI_API_KEY)"),
               !key.contains("your_actual_key") {
                print("✅ API Key retrieved successfully")
                return key
            }
        }
        
        // Detailed error logging
        print("\n❌ OpenAI API Key Configuration Error")
        print("Retrieval Methods:")
        for (index, method) in retrievalMethods.enumerated() {
            print("Method \(index + 1): \(method() ?? "nil")")
        }
        
        print("\nTroubleshooting Steps:")
        print("1. Verify Config.xcconfig contains: OPENAI_API_KEY = your_actual_key")
        print("2. Check Info.plist has OPENAI_API_KEY key")
        print("3. Ensure environment variables are set")
        print("4. Clean build folder and rebuild")
        
        // Provide a meaningful error message
        fatalError("""
        OpenAI API key could not be retrieved. 
        Please check your configuration in Config.xcconfig, Info.plist, and environment variables.
        """)
    }
    private let endpoint = "https://api.openai.com/v1/chat/completions"
    
    func generateScript(from article: NewsItem) async throws -> String {
        let prompt = """
        Create a short-form video script that captures attention and delivers key information concisely:

        Script Guidelines:
        1. Total Script Length: 30-45 seconds
        2. Hook: Start with a punchy, attention-grabbing opening (3-5 seconds)
        3. Key Information: Distill the most critical 2-3 points from the article
        4. Tone: Conversational, energetic, and direct
        5. Structure:
           - Headline-style opening
           - Quick facts with impact
           - Minimal jargon
           - Clear, memorable conclusion

        Source Article Details:
        Title: \(article.title)
        Content: \(article.description)
        Categories: \(article.category.joined(separator: ", "))

        Delivery Style Inspiration:
        - Think TikTok News
        - Similar to Instagram Reels news segments
        - Fast-paced, informative, and shareable

        Output Format:
        [HOOK]
        [KEY POINT 1]
        [KEY POINT 2]
        [BRIEF CONCLUSION/CALL TO ACTION]
        """
        
        let messages: [[String: Any]] = [
            ["role": "system", "content": "You are an expert video script writer and subject matter researcher. Your goal is to create engaging scripts that not only cover the article's content but also provide valuable additional context and insights. Make complex topics accessible while maintaining depth and accuracy."],
            ["role": "user", "content": prompt]
        ]
        
        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": messages,
            "temperature": 0.7,
            "max_tokens": 500
        ]
        
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "OpenAIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to generate script"])
        }
        
        guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = jsonResponse["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(domain: "OpenAIService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
        }
        
        return content
    }
}
