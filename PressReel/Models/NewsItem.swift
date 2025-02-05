import Foundation
import FirebaseFirestore

struct NewsItem: Identifiable {
    let id: String
    let title: String
    let description: String
    let url: String
    let author: String?
    let image: String?
    let language: String
    let category: [String]
    let published: Date
    let searchableText: [String]
    let searchableTitle: [String]
    
    var likes: Int
    var saves: Int
    var userInteractions: [String: [String: Any]]
    
    init(id: String, title: String, description: String, url: String, author: String?, image: String?, language: String, category: [String], published: Date) {
        self.id = id
        self.title = title
        self.description = description
        self.url = url
        self.author = author
        self.image = image
        self.language = language
        self.category = category
        self.published = published
        self.likes = 0
        self.saves = 0
        self.userInteractions = [:]
        
        // Generate searchable text from title and description
        let text = "\(title) \(description)".lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        self.searchableText = Array(Set(text)) // Remove duplicates
        
        // Generate searchable text from title only
        let titleWords = title.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        self.searchableTitle = Array(Set(titleWords)) // Remove duplicates
    }
    
    init?(dictionary: [String: Any]) {
        print("Attempting to parse NewsItem from dictionary: \(dictionary)")
        
        // Required fields
        guard let id = dictionary["id"] as? String,
              let title = dictionary["title"] as? String,
              let description = dictionary["description"] as? String,
              let url = dictionary["url"] as? String else {
            print("Failed to parse required fields:")
            if dictionary["id"] as? String == nil { print("- Missing id") }
            if dictionary["title"] as? String == nil { print("- Missing title") }
            if dictionary["description"] as? String == nil { print("- Missing description") }
            if dictionary["url"] as? String == nil { print("- Missing url") }
            return nil
        }
        
        // Handle published date
        let published: Date
        if let timestamp = dictionary["published"] as? Timestamp {
            published = timestamp.dateValue()
        } else if let dateString = dictionary["published"] as? String {
            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: dateString) {
                published = date
            } else {
                print("Failed to parse published date from string: \(dateString)")
                return nil
            }
        } else {
            print("Failed to parse published date - neither Timestamp nor String found")
            return nil
        }
        
        // Optional fields with defaults
        let language = dictionary["language"] as? String ?? "en"
        let category = dictionary["category"] as? [String] ?? []
        
        self.id = id
        self.title = title
        self.description = description
        self.url = url
        self.author = dictionary["author"] as? String
        self.image = dictionary["image"] as? String
        self.language = language
        self.category = category
        self.published = published
        self.likes = dictionary["likes"] as? Int ?? 0
        self.saves = dictionary["saves"] as? Int ?? 0
        self.userInteractions = dictionary["userInteractions"] as? [String: [String: Any]] ?? [:]
        
        // Generate searchable text if not present in dictionary
        if let existingSearchableText = dictionary["searchableText"] as? [String] {
            self.searchableText = existingSearchableText
        } else {
            let text = "\(title) \(description)".lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
            self.searchableText = Array(Set(text))
        }
        
        // Generate searchable title if not present in dictionary
        if let existingSearchableTitle = dictionary["searchableTitle"] as? [String] {
            self.searchableTitle = existingSearchableTitle
        } else {
            let titleWords = title.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
            self.searchableTitle = Array(Set(titleWords))
        }
        
        print("Successfully created NewsItem with id: \(id)")
    }
    
    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "title": title,
            "description": description,
            "url": url,
            "language": language,
            "category": category,
            "published": Timestamp(date: published),
            "likes": likes,
            "saves": saves,
            "userInteractions": userInteractions,
            "searchableText": searchableText,
            "searchableTitle": searchableTitle
        ]
        
        if let author = author {
            dict["author"] = author
        }
        if let image = image {
            dict["image"] = image
        }
        
        return dict
    }
}

struct UserInteraction {
    var isLiked: Bool
    var isSaved: Bool
    var lastViewed: Date?
    
    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "isLiked": isLiked,
            "isSaved": isSaved
        ]
        if let lastViewed = lastViewed {
            dict["lastViewed"] = Timestamp(date: lastViewed)
        }
        return dict
    }
    
    static func from(dictionary: [String: Any]) -> UserInteraction {
        let lastViewed: Date?
        if let timestamp = dictionary["lastViewed"] as? Timestamp {
            lastViewed = timestamp.dateValue()
        } else {
            lastViewed = nil
        }
        
        return UserInteraction(
            isLiked: dictionary["isLiked"] as? Bool ?? false,
            isSaved: dictionary["isSaved"] as? Bool ?? false,
            lastViewed: lastViewed
        )
    }
} 