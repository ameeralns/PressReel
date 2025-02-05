import Foundation
import FirebaseFirestore

struct Script: Identifiable, Codable {
    let id: String
    let userId: String
    let newsItemId: String
    let content: String
    let createdAt: Date
    let title: String
    let duration: Int
    let articleTitle: String
    let articleUrl: String
    
    var dictionary: [String: Any] {
        return [
            "id": id,
            "userId": userId,
            "newsItemId": newsItemId,
            "content": content,
            "createdAt": createdAt,
            "title": title,
            "duration": duration,
            "articleTitle": articleTitle,
            "articleUrl": articleUrl
        ]
    }
}
