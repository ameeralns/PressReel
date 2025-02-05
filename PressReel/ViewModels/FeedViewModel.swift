import SwiftUI
import Firebase
import FirebaseFirestore
import FirebaseAuth

class FeedViewModel: ObservableObject {
    private let openAIService = OpenAIService()
    private let scriptService = ScriptService()
    @Published var newsItems: [NewsItem] = []
    @Published var isLoading = false
    @Published var error: Error?
    @Published var hasMoreContent = true
    @Published var searchText = ""
    @Published var isSearching = false
    
    private var lastDocument: DocumentSnapshot?
    private let pageSize = 10
    private var selectedCategory: String?
    private let newsService = NewsService.shared
    private var searchTask: Task<Void, Never>?
    private var searchWorkItem: DispatchWorkItem?
    let userId: String
    
    init(userId: String) {
        self.userId = userId
        print("Initializing FeedViewModel with userId: \(userId)")
        
        // Load initial data
        Task {
            await refreshFeed()
        }
    }
    
    func performSearch() {
        isSearching = true
        
        // Cancel any existing work item
        searchWorkItem?.cancel()
        
        // Create a new work item
        let workItem = DispatchWorkItem { [weak self] in
            Task { [weak self] in
                await self?.refreshFeed()
                await MainActor.run {
                    self?.isSearching = false
                }
            }
        }
        
        // Store the work item
        searchWorkItem = workItem
        
        // Schedule the work item with a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }
    
    func refreshFeed() async {
        print("Refreshing feed...")
        await MainActor.run {
            isLoading = true
            error = nil
        }
        
        do {
            let searchTerms = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let (news, lastDoc) = try await newsService.getNews(
                category: selectedCategory,
                searchQuery: searchTerms.isEmpty ? nil : searchTerms,
                pageSize: pageSize,
                lastDocument: nil // Reset pagination
            )
            
            await MainActor.run {
                print("Loaded \(news.count) articles")
                self.newsItems = news
                self.lastDocument = lastDoc
                self.hasMoreContent = news.count == pageSize
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                print("Error refreshing feed: \(error.localizedDescription)")
                self.error = error
                self.isLoading = false
            }
        }
    }
    
    func loadMoreIfNeeded(currentItem: NewsItem) {
        guard let lastItem = newsItems.last,
              lastItem.id == currentItem.id,
              !isLoading,
              hasMoreContent else {
            return
        }
        
        Task {
            await loadNextPage()
        }
    }
    
    private func loadNextPage() async {
        guard !isLoading, hasMoreContent else { return }
        
        await MainActor.run {
            isLoading = true
            error = nil
        }
        
        do {
            let (news, lastDoc) = try await newsService.getNews(
                category: selectedCategory,
                searchQuery: searchText.isEmpty ? nil : searchText,
                pageSize: pageSize,
                lastDocument: lastDocument
            )
            
            await MainActor.run {
                // Filter out any duplicates before appending
                let newUniqueItems = news.filter { newItem in
                    !self.newsItems.contains { $0.id == newItem.id }
                }
                
                if !newUniqueItems.isEmpty {
                    self.newsItems.append(contentsOf: newUniqueItems)
                }
                
                self.lastDocument = lastDoc
                self.hasMoreContent = news.count == pageSize
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error
                self.isLoading = false
            }
        }
    }
    
    func toggleLike(for item: NewsItem) async {
        let interaction = UserInteraction(
            isLiked: !(item.userInteractions[userId]?["isLiked"] as? Bool ?? false),
            isSaved: item.userInteractions[userId]?["isSaved"] as? Bool ?? false,
            lastViewed: item.userInteractions[userId]?["lastViewed"] as? Date
        )
        
        do {
            try await newsService.updateUserInteraction(
                newsId: item.id,
                userId: userId,
                interaction: interaction
            )
        } catch {
            self.error = error
        }
    }
    
    func toggleSave(for item: NewsItem) async {
        let interaction = UserInteraction(
            isLiked: item.userInteractions[userId]?["isLiked"] as? Bool ?? false,
            isSaved: !(item.userInteractions[userId]?["isSaved"] as? Bool ?? false),
            lastViewed: item.userInteractions[userId]?["lastViewed"] as? Date
        )
        
        do {
            try await newsService.updateUserInteraction(
                newsId: item.id,
                userId: userId,
                interaction: interaction
            )
        } catch {
            self.error = error
        }
    }
    
    func updateCategory(_ category: String?) {
        selectedCategory = category
        Task {
            await refreshFeed()
        }
    }
    
    func generateScript(for item: NewsItem) async throws -> Script {
        let script = try await openAIService.generateScript(from: item)
        
        let newScript = Script(
            id: UUID().uuidString,
            userId: userId,
            newsItemId: item.id,
            content: script,
            createdAt: Date(),
            title: "Script for: \(item.title)",
            duration: 60,
            articleTitle: item.title,
            articleUrl: item.url
        )
        
        try await scriptService.saveScript(newScript)
        return newScript
    }
} 