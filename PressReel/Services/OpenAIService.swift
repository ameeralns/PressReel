import Foundation

class OpenAIService {
    private let apiKey: String = {
        guard let apiKey = Bundle.main.infoDictionary?["OPENAI_API_KEY"] as? String else {
            fatalError("OpenAI API key not found in configuration")
        }
        return apiKey
    }()
    private let endpoint = "https://api.openai.com/v1/chat/completions"
    
    func generateScript(from article: NewsItem) async throws -> String {
        let prompt = """
        Create an informative video script for the following article:
        Title: \(article.title)
        Content: \(article.description)
        Categories: \(article.category.joined(separator: ", "))
        
        Requirements:
        1. Structure:
           - Engaging introduction
           - Main points with supporting details
           - Additional context and background information
           - Clear conclusion with key takeaways
        
        2. Content Enhancement:
           - Provide relevant background information about the topic
           - Explain any technical terms or complex concepts
           - Include supporting statistics or data when relevant
           - Connect the topic to broader trends or implications
        
        3. Style:
           - Conversational and engaging tone
           - Clear and concise language
           - Natural transitions between points
           - Timed for 1-2 minutes of speaking
        
        Make the script informative and engaging while helping viewers understand the broader context of the topic.
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
