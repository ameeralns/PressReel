import SwiftUI
import Firebase
import FirebaseFirestore

struct FeedView: View {
    @StateObject private var viewModel: FeedViewModel
    @State private var showNotifications = false
    @FocusState private var isSearchFocused: Bool
    
    init(userId: String) {
        print("Initializing FeedView with userId: \(userId)")
        _viewModel = StateObject(wrappedValue: FeedViewModel(userId: userId))
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Custom Navigation Bar
                HStack {
                    Text("Feed")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: { showNotifications = true }) {
                        Image(systemName: "bell.fill")
                            .foregroundColor(.white)
                    }
                }
                .padding()
                
                // Search Bar
                HStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white.opacity(0.6))
                        
                        TextField("Search articles...", text: $viewModel.searchText)
                            .textFieldStyle(.plain)
                            .foregroundColor(.white)
                            .accentColor(.white)
                            .focused($isSearchFocused)
                            .autocorrectionDisabled()
                            .onChange(of: viewModel.searchText) { newValue in
                                viewModel.performSearch()
                            }
                        
                        if !viewModel.searchText.isEmpty {
                            Button(action: {
                                viewModel.searchText = ""
                                isSearchFocused = false
                                Task {
                                    await viewModel.refreshFeed()
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.bottom)
                
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if viewModel.newsItems.isEmpty && viewModel.isLoading {
                            // Loading State
                            VStack {
                                Spacer()
                                    .frame(height: 100)
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(1.5)
                                Text("Loading articles...")
                                    .foregroundColor(.white.opacity(0.7))
                                    .padding(.top)
                            }
                        } else if viewModel.newsItems.isEmpty {
                            // Empty State
                            VStack {
                                Spacer()
                                    .frame(height: 100)
                                Image(systemName: "newspaper")
                                    .font(.system(size: 50))
                                    .foregroundColor(.white.opacity(0.7))
                                if viewModel.searchText.isEmpty {
                                    Text("No articles available")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .padding(.top)
                                } else {
                                    Text("No articles found")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .padding(.top)
                                    Text("Try different keywords")
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.7))
                                        .padding(.top, 4)
                                }
                                Button(action: {
                                    Task {
                                        await viewModel.refreshFeed()
                                    }
                                }) {
                                    Text("Refresh")
                                        .foregroundColor(.blue)
                                        .padding(.top, 8)
                                }
                            }
                        } else {
                            // News Feed
                            ForEach(viewModel.newsItems) { item in
                                NewsItemCard(
                                    item: item,
                                    isLiked: item.userInteractions[viewModel.userId]?["isLiked"] as? Bool ?? false,
                                    isSaved: item.userInteractions[viewModel.userId]?["isSaved"] as? Bool ?? false,
                                    onLike: { Task { await viewModel.toggleLike(for: item) } },
                                    onSave: { Task { await viewModel.toggleSave(for: item) } },
                                    userId: viewModel.userId
                                )
                                .onAppear {
                                    viewModel.loadMoreIfNeeded(currentItem: item)
                                }
                            }
                            
                            if viewModel.isLoading {
                                ProgressView()
                                    .tint(.white)
                                    .padding()
                            }
                        }
                    }
                    .padding()
                }
                .refreshable {
                    await viewModel.refreshFeed()
                }
            }
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.error?.localizedDescription ?? "An error occurred")
        }
        .onAppear {
            Task {
                await viewModel.refreshFeed()
            }
        }
        .onChange(of: isSearchFocused) { focused in
            if !focused && viewModel.searchText.isEmpty {
                Task {
                    await viewModel.refreshFeed()
                }
            }
        }
    }
}

struct NewsItemCard: View {
    let item: NewsItem
    let isLiked: Bool
    let isSaved: Bool
    let onLike: () -> Void
    let onSave: () -> Void
    @State private var imageData: Data?
    @State private var showArticleView = false
    let userId: String
    
    private func validateURL(_ urlString: String?) -> URL? {
        guard let urlString = urlString,
              !urlString.isEmpty,
              let url = URL(string: urlString),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()) else {
            return nil
        }
        return url
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Thumbnail
            if let imageURL = validateURL(item.image) {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        Rectangle()
                            .fill(Color.white.opacity(0.1))
                            .aspectRatio(16/9, contentMode: .fit)
                            .overlay(
                                ProgressView()
                                    .tint(.white)
                            )
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(16/9, contentMode: .fit)
                    case .failure:
                        Rectangle()
                            .fill(Color.white.opacity(0.1))
                            .aspectRatio(16/9, contentMode: .fit)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(.white)
                            )
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .aspectRatio(16/9, contentMode: .fit)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.white)
                    )
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(item.title)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text(item.description)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(2)
                
                HStack {
                    if let author = item.author {
                        Text(author)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
                    Spacer()
                    
                    Text(timeAgo(from: item.published))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
                
                HStack(spacing: 20) {
                    Button(action: onLike) {
                        HStack(spacing: 4) {
                            Image(systemName: isLiked ? "heart.fill" : "heart")
                                .foregroundColor(isLiked ? .red : .white.opacity(0.6))
                        }
                    }
                    
                    Button(action: onSave) {
                        HStack(spacing: 4) {
                            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                                .foregroundColor(isSaved ? .red : .white.opacity(0.6))
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: { showArticleView = true }) {
                        Text("Read More")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.red)
                    }
                    
                    ShareLink(item: URL(string: item.url)!) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
        )
        .sheet(isPresented: $showArticleView) {
            NavigationView {
                ArticleView(item: item, userId: userId)
            }
        }
    }
    
    private func timeAgo(from date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.minute, .hour, .day], from: date, to: now)
        
        if let day = components.day, day > 0 {
            return "\(day)d ago"
        } else if let hour = components.hour, hour > 0 {
            return "\(hour)h ago"
        } else if let minute = components.minute, minute > 0 {
            return "\(minute)m ago"
        } else {
            return "Just now"
        }
    }
} 