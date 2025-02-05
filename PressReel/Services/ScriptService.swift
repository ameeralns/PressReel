import Foundation
import FirebaseFirestore

class ScriptService {
    private let db = Firestore.firestore()
    
    func saveScript(_ script: Script) async throws {
        try await db.collection("scripts").document(script.id).setData(script.dictionary)
    }
    
    func getScripts(for userId: String) async throws -> [Script] {
        let snapshot = try await db.collection("scripts")
            .whereField("userId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .getDocuments()
        
        return try snapshot.documents.compactMap { document -> Script? in
            let data = document.data()
            
            guard let id = data["id"] as? String,
                  let userId = data["userId"] as? String,
                  let newsItemId = data["newsItemId"] as? String,
                  let content = data["content"] as? String,
                  let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
                  let title = data["title"] as? String,
                  let duration = data["duration"] as? Int,
                  let articleTitle = data["articleTitle"] as? String,
                  let articleUrl = data["articleUrl"] as? String else {
                return nil
            }
            
            return Script(
                id: id,
                userId: userId,
                newsItemId: newsItemId,
                content: content,
                createdAt: createdAt,
                title: title,
                duration: duration,
                articleTitle: articleTitle,
                articleUrl: articleUrl
            )
        }
    }
    
    func deleteScript(_ scriptId: String, userId: String) async throws {
        let document = try await db.collection("scripts").document(scriptId).getDocument()
        guard let data = document.data(),
              let documentUserId = data["userId"] as? String,
              documentUserId == userId else {
            throw NSError(domain: "ScriptService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unauthorized to delete this script"])
        }
        
        try await db.collection("scripts").document(scriptId).delete()
    }
}
