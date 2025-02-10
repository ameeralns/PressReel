import Foundation

// Import our models
@_implementationOnly import PressReel

actor PixabayService {
    // MARK: - Properties
    private let apiKey: String
    private let videoBaseURL = "https://pixabay.com/api/videos/"
    private let imageBaseURL = "https://pixabay.com/api/"
    private let cache = NSCache<NSString, NSArray>()
    
    // MARK: - Initialization
    init() {
        guard let apiKey = Bundle.main.infoDictionary?["PIXABAY_API_KEY"] as? String else {
            fatalError("Pixabay API Key not found in configuration")
        }
        self.apiKey = apiKey
        setupCache()
    }
    
    // MARK: - Public Methods
    
    /// Fetches all necessary media for a scene from the AI analysis
    func fetchMediaForScene(_ scene: VideoScene) async throws -> SceneMedia {
        // First, try cache
        let cacheKey = "\(scene.id)-\(scene.visualType)"
        if let cachedMedia = cache.object(forKey: cacheKey as NSString) as? [PixabayMedia] {
            return SceneMedia(primary: cachedMedia, background: [], overlays: [])
        }
        
        // Combine and process keywords for optimal search
        let searchTerms = processKeywords(
            keywords: scene.keywords,
            description: scene.description,
            mood: scene.mood
        )
        
        // Fetch primary media based on visual type
        let primaryMedia = try await fetchPrimaryMedia(
            for: scene.visualType,
            keywords: searchTerms,
            duration: Int(ceil(scene.duration))
        )
        
        guard !primaryMedia.isEmpty else {
            throw PixabayError.noSuitableMediaFound
        }
        
        // Cache the results
        cache.setObject(primaryMedia as NSArray, forKey: cacheKey as NSString)
        
        // For b-roll scenes, we might want background footage
        var backgroundMedia: [PixabayMedia] = []
        if scene.visualType == .bRoll {
            backgroundMedia = try await searchVideos(
                keywords: ["abstract", "background", scene.mood],
                duration: Int(ceil(scene.duration)),
                category: "backgrounds",
                minWidth: 1280
            )
        }
        
        return SceneMedia(
            primary: primaryMedia,
            background: backgroundMedia,
            overlays: []  // Overlays will be handled separately
        )
    }
    
    // MARK: - Private Methods
    private func setupCache() {
        cache.countLimit = 100 // Maximum number of scenes to cache
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB cache limit
    }
    
    private func fetchPrimaryMedia(for visualType: VisualType, keywords: [String], duration: Int) async throws -> [PixabayMedia] {
        switch visualType {
        case .bRoll:
            return try await searchVideos(
                keywords: keywords,
                duration: duration,
                category: nil,
                minWidth: 1920 // Full HD minimum
            )
        case .talking:
            return try await searchVideos(
                keywords: keywords,
                duration: duration,
                category: "people",
                minWidth: 1920
            )
        case .staticImage:
            return try await searchImages(
                keywords: keywords,
                category: nil,
                minWidth: 1920
            )
        case .overlay:
            return [] // Overlays are handled separately
        }
    }
    
    private func processKeywords(keywords: [String], description: String, mood: String) -> [String] {
        var searchTerms = Set(keywords)
        
        // Extract additional keywords from description
        let descriptionWords = description
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count > 3 } // Filter out small words
        searchTerms.formUnion(descriptionWords)
        
        // Add mood if relevant
        if !mood.isEmpty && mood != "neutral" {
            searchTerms.insert(mood)
        }
        
        // Process and optimize keywords
        return searchTerms
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
            .prefix(5) // Pixabay works best with up to 5 keywords
            .map { $0.replacingOccurrences(of: " ", with: "+") }
    }
    
    private func searchVideos(keywords: [String], duration: Int, category: String?, minWidth: Int = 1280) async throws -> [PixabayMedia] {
        var components = URLComponents(string: videoBaseURL)!
        
        var queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "q", value: keywords.joined(separator: "+")),
            URLQueryItem(name: "per_page", value: "10"),
            URLQueryItem(name: "min_duration", value: "\(max(1, duration - 2))"),
            URLQueryItem(name: "max_duration", value: "\(duration + 2))"),
            URLQueryItem(name: "order", value: "relevance"),
            URLQueryItem(name: "min_width", value: "\(minWidth)"),
            URLQueryItem(name: "safesearch", value: "true")
        ]
        
        if let category {
            queryItems.append(URLQueryItem(name: "category", value: category))
        }
        
        components.queryItems = queryItems
        
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PixabayError.requestFailed
        }
        
        let searchResponse = try JSONDecoder().decode(PixabayVideoResponse.self, from: data)
        guard !searchResponse.hits.isEmpty else {
            throw PixabayError.noSuitableMediaFound
        }
        
        return searchResponse.hits.map { .video($0) }
    }
    
    private func searchImages(keywords: [String], category: String?, minWidth: Int = 1920) async throws -> [PixabayMedia] {
        var components = URLComponents(string: imageBaseURL)!
        
        var queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "q", value: keywords.joined(separator: "+")),
            URLQueryItem(name: "per_page", value: "10"),
            URLQueryItem(name: "image_type", value: "photo"),
            URLQueryItem(name: "orientation", value: "horizontal"),
            URLQueryItem(name: "order", value: "relevance"),
            URLQueryItem(name: "min_width", value: "\(minWidth)"),
            URLQueryItem(name: "safesearch", value: "true")
        ]
        
        if let category {
            queryItems.append(URLQueryItem(name: "category", value: category))
        }
        
        components.queryItems = queryItems
        
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PixabayError.requestFailed
        }
        
        let searchResponse = try JSONDecoder().decode(PixabayImageResponse.self, from: data)
        guard !searchResponse.hits.isEmpty else {
            throw PixabayError.noSuitableMediaFound
        }
        
        return searchResponse.hits.map { .image($0) }
    }
}

// MARK: - Models
struct SceneMedia {
    let primary: [PixabayMedia]    // Main scene content
    let background: [PixabayMedia] // Optional background footage
    let overlays: [PixabayMedia]   // Overlay content if needed
}

enum PixabayMedia {
    case video(PixabayVideo)
    case image(PixabayImage)
    
    var url: URL {
        switch self {
        case .video(let video):
            return video.videos.large.url
        case .image(let image):
            return image.largeImageURL
        }
    }
    
    var width: Int {
        switch self {
        case .video(let video):
            return video.width
        case .image(let image):
            return image.imageWidth
        }
    }
    
    var height: Int {
        switch self {
        case .video(let video):
            return video.height
        case .image(let image):
            return image.imageHeight
        }
    }
}

struct PixabayVideoResponse: Codable {
    let hits: [PixabayVideo]
}

struct PixabayImageResponse: Codable {
    let hits: [PixabayImage]
}

struct PixabayVideo: Codable {
    let videos: VideoURLs
    let tags: String
    let duration: Int
    let picture_id: String
    let width: Int
    let height: Int
}

struct VideoURLs: Codable {
    let large: VideoURL
    let medium: VideoURL
    let small: VideoURL
}

struct VideoURL: Codable {
    let url: URL
    let width: Int
    let height: Int
    let size: Int
}

struct PixabayImage: Codable {
    let largeImageURL: URL
    let tags: String
    let imageWidth: Int
    let imageHeight: Int
}

enum PixabayError: LocalizedError {
    case requestFailed
    case invalidResponse
    case noSuitableMediaFound
    
    var errorDescription: String? {
        switch self {
        case .requestFailed:
            return "Failed to fetch media from Pixabay"
        case .invalidResponse:
            return "Received invalid response from Pixabay"
        case .noSuitableMediaFound:
            return "No suitable media found for the scene"
        }
    }
} 