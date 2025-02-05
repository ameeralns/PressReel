import SwiftUI
import SafariServices
import Firebase
import FirebaseFirestore

struct ArticleView: View {
    let item: NewsItem
    let userId: String
    @Environment(\.dismiss) private var dismiss
    @State private var showWebView = false
    @State private var isLiked: Bool
    @State private var isSaved: Bool
    
    init(item: NewsItem, userId: String) {
        self.item = item
        self.userId = userId
        _isLiked = State(initialValue: item.userInteractions[userId]?["isLiked"] as? Bool ?? false)
        _isSaved = State(initialValue: item.userInteractions[userId]?["isSaved"] as? Bool ?? false)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Image
                if let imageURL = URL(string: item.image ?? "") {
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
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    // Title
                    Text(item.title)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    // Metadata
                    HStack {
                        if let author = item.author {
                            Text("By \(author)")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        
                        Spacer()
                        
                        Text(formatDate(item.published))
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    // Categories
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(item.category, id: \.self) { category in
                                Text(category)
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.red.opacity(0.2))
                                    .foregroundColor(.red)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    
                    // Description
                    Text(item.description)
                        .font(.body)
                        .foregroundColor(.white.opacity(0.9))
                        .lineSpacing(8)
                    
                    // Action Buttons
                    HStack(spacing: 20) {
                        Button(action: {
                            isLiked.toggle()
                            Task {
                                await toggleLike()
                            }
                        }) {
                            Label(
                                "\(item.likes)",
                                systemImage: isLiked ? "heart.fill" : "heart"
                            )
                            .foregroundColor(isLiked ? .red : .white.opacity(0.6))
                        }
                        
                        Button(action: {
                            isSaved.toggle()
                            Task {
                                await toggleSave()
                            }
                        }) {
                            Label(
                                "\(item.saves)",
                                systemImage: isSaved ? "bookmark.fill" : "bookmark"
                            )
                            .foregroundColor(isSaved ? .red : .white.opacity(0.6))
                        }
                        
                        Spacer()
                        
                        ShareLink(item: URL(string: item.url)!) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    .padding(.top, 8)
                    
                    // Read Full Article Button
                    Button(action: { showWebView = true }) {
                        Text("Read Full Article")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .cornerRadius(12)
                    }
                    .padding(.top, 16)
                }
                .padding()
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ShareLink(item: URL(string: item.url)!) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(.white)
                }
            }
        }
        .sheet(isPresented: $showWebView) {
            SafariView(url: URL(string: item.url)!)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func toggleLike() async {
        let interaction = UserInteraction(
            isLiked: isLiked,
            isSaved: isSaved,
            lastViewed: Date()
        )
        
        do {
            try await NewsService.shared.updateUserInteraction(
                newsId: item.id,
                userId: userId,
                interaction: interaction
            )
        } catch {
            // Revert UI state if the update fails
            isLiked.toggle()
        }
    }
    
    private func toggleSave() async {
        let interaction = UserInteraction(
            isLiked: isLiked,
            isSaved: isSaved,
            lastViewed: Date()
        )
        
        do {
            try await NewsService.shared.updateUserInteraction(
                newsId: item.id,
                userId: userId,
                interaction: interaction
            )
        } catch {
            // Revert UI state if the update fails
            isSaved.toggle()
        }
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> SFSafariViewController {
        return SFSafariViewController(url: url)
    }
    
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
} 