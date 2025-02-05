import Foundation

enum CurrentsAPIError: Error {
    case invalidURL
    case invalidResponse
    case decodingError
    case networkError(Error)
    case missingAPIKey
}

class CurrentsAPIClient {
    private let apiKey: String
    private let baseURL = "https://api.currentsapi.services/v1"
    
    init(apiKey: String? = nil) {
        // Use provided API key or try to get from environment
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["CURRENTS_API_KEY"] ?? ""
    }
    
    func fetchLatestNews() async throws -> [NewsItem] {
        guard !apiKey.isEmpty else {
            throw CurrentsAPIError.missingAPIKey
        }
        
        guard let url = URL(string: "\(baseURL)/latest-news?apiKey=\(apiKey)&language=en") else {
            throw CurrentsAPIError.invalidURL
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw CurrentsAPIError.invalidResponse
            }
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            struct APIResponse: Codable {
                let news: [APINewsItem]
            }
            
            struct APINewsItem: Codable {
                let id: String
                let title: String
                let description: String
                let url: String
                let author: String?
                let image: String?
                let language: String
                let category: [String]
                let published: String
            }
            
            let apiResponse = try decoder.decode(APIResponse.self, from: data)
            let dateFormatter = ISO8601DateFormatter()
            
            return apiResponse.news.map { item in
                NewsItem(
                    id: item.id,
                    title: item.title,
                    description: item.description,
                    url: item.url,
                    author: item.author,
                    image: item.image,
                    language: item.language,
                    category: item.category,
                    published: dateFormatter.date(from: item.published) ?? Date()
                )
            }
        } catch {
            throw CurrentsAPIError.networkError(error)
        }
    }
} 