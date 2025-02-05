import Foundation
import FirebaseFirestore
import FirebaseAuth

class NewsService {
    static let shared = NewsService()
    private let db = Firestore.firestore()
    private var currentsAPI: CurrentsAPIClient
    private static var apiKey: String?
    
    private init() {
        self.currentsAPI = CurrentsAPIClient(apiKey: NewsService.apiKey)
    }
    
    // Static method to initialize with API key
    static func initialize(withAPIKey apiKey: String) {
        NewsService.apiKey = apiKey
        shared.currentsAPI = CurrentsAPIClient(apiKey: apiKey)
        print("NewsService initialized with API key")
    }
    
    func fetchAndUpdateNews() async throws {
        // This should only be called by admin/backend processes
        guard let currentUser = Auth.auth().currentUser,
              // Add your admin UIDs here
              ["YOUR_ADMIN_UID_1", "YOUR_ADMIN_UID_2"].contains(currentUser.uid) else {
            print("Cannot fetch news: User not authorized")
            throw NSError(domain: "NewsService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authorized to fetch news"])
        }
        
        print("Fetching news from CurrentsAPI...")
        let news = try await currentsAPI.fetchLatestNews()
        print("Fetched \(news.count) articles, updating Firestore...")
        try await updateFirestoreNews(news)
        print("Successfully updated Firestore with new articles")
    }
    
    private func updateFirestoreNews(_ news: [NewsItem]) async throws {
        let batch = db.batch()
        
        for item in news {
            let docRef = db.collection("news").document(item.id)
            batch.setData(item.dictionary, forDocument: docRef, merge: true)
        }
        
        try await batch.commit()
    }
    
    func getNews(
        category: String? = nil,
        searchQuery: String? = nil,
        pageSize: Int = 10,
        lastDocument: DocumentSnapshot? = nil
    ) async throws -> (news: [NewsItem], lastDocument: DocumentSnapshot?) {
        print("Getting news from Firestore - pageSize: \(pageSize), category: \(category ?? "all"), search: \(searchQuery ?? "none")")
        
        // Start with the base collection
        let collection = db.collection("news")
        var query: Query
        
        // Build query based on the available indexes
        if let searchQuery = searchQuery, !searchQuery.isEmpty {
            // Process search query
            let searchTerms = searchQuery.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
            
            if !searchTerms.isEmpty {
                print("Searching with terms: \(searchTerms)")
                // Use searchableText index and filter category client-side
                query = collection
                    .whereField("searchableText", arrayContainsAny: searchTerms)
                    .order(by: "published", descending: true)
            } else {
                // Fallback to category-only if no valid search terms
                if let category = category {
                    query = collection
                        .whereField("category", arrayContains: category)
                        .order(by: "published", descending: true)
                } else {
                    query = collection
                        .order(by: "published", descending: true)
                }
            }
        } else if let category = category {
            // Case 2: Category only
            query = collection
                .whereField("category", arrayContains: category)
                .order(by: "published", descending: true)
        } else {
            // Case 3: No filters
            query = collection
                .order(by: "published", descending: true)
        }
        
        // Apply pagination
        let paginatedQuery = lastDocument != nil ?
            query.start(afterDocument: lastDocument!).limit(to: pageSize) :
            query.limit(to: pageSize)
        
        do {
            print("Executing Firestore query...")
            let snapshot = try await paginatedQuery.getDocuments()
            print("Received \(snapshot.documents.count) documents from Firestore")
            
            let items = snapshot.documents.compactMap { document -> NewsItem? in
                var documentData = document.data()
                if documentData["id"] == nil {
                    documentData["id"] = document.documentID
                }
                return NewsItem(dictionary: documentData)
            }
            
            // Apply additional filtering client-side if needed
            var filteredItems = items
            
            // Apply category filter if we're searching (since we can't use both array contains)
            if let category = category,
               let searchQuery = searchQuery,
               !searchQuery.isEmpty {
                filteredItems = items.filter { $0.category.contains(category) }
            }
            
            // Apply search filtering and sorting
            if let searchQuery = searchQuery, !searchQuery.isEmpty {
                let searchTerms = searchQuery.lowercased()
                    .components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .filter { !$0.isEmpty }
                
                if !searchTerms.isEmpty {
                    filteredItems = filteredItems
                        .filter { item in
                            // Check if any search term matches exactly in title or description
                            let titleWords = Set(item.title.lowercased()
                                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                                .filter { !$0.isEmpty })
                            let descWords = Set(item.description.lowercased()
                                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                                .filter { !$0.isEmpty })
                            
                            return searchTerms.contains { term in
                                titleWords.contains(term) || descWords.contains(term)
                            }
                        }
                        .sorted { item1, item2 in
                            // Sort by relevance:
                            // 1. Title exact matches
                            // 2. Description exact matches
                            // 3. Published date
                            let title1Words = Set(item1.title.lowercased()
                                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                                .filter { !$0.isEmpty })
                            let title2Words = Set(item2.title.lowercased()
                                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                                .filter { !$0.isEmpty })
                            
                            let title1Matches = searchTerms.filter { title1Words.contains($0) }.count
                            let title2Matches = searchTerms.filter { title2Words.contains($0) }.count
                            
                            if title1Matches != title2Matches {
                                return title1Matches > title2Matches
                            }
                            
                            return item1.published > item2.published
                        }
                }
            }
            
            print("Returning \(filteredItems.count) filtered items")
            return (filteredItems, snapshot.documents.last)
        } catch let error as NSError {
            if error.domain == "FIRFirestoreErrorDomain" && error.code == 9 {
                print("Index error: Please create the required composite index in Firebase Console")
                throw NSError(
                    domain: "NewsService",
                    code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Search functionality is being set up. Please try again in a few minutes."
                    ]
                )
            }
            throw error
        }
    }
    
    func updateUserInteraction(newsId: String, userId: String, interaction: UserInteraction) async throws {
        try await db.collection("news").document(newsId).updateData([
            "userInteractions.\(userId)": interaction.dictionary,
            "likes": FieldValue.increment(interaction.isLiked ? Int64(1) : Int64(-1)),
            "saves": FieldValue.increment(interaction.isSaved ? Int64(1) : Int64(-1))
        ])
    }
    
    func listenToNewsUpdates(completion: @escaping ([NewsItem]) -> Void) {
        print("Setting up real-time news updates listener")
        db.collection("news")
            .order(by: "published", descending: true)
            .limit(to: 20)
            .addSnapshotListener { querySnapshot, error in
                if let error = error {
                    print("Error listening to news updates: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = querySnapshot?.documents else {
                    print("No documents in snapshot")
                    return
                }
                
                print("Received \(documents.count) documents in real-time update")
                let news = documents.compactMap { document in
                    NewsItem(dictionary: document.data())
                }
                print("Successfully parsed \(news.count) NewsItems from real-time update")
                
                completion(news.sorted(by: { $0.published > $1.published }))
            }
    }
} 

