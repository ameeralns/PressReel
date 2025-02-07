import SwiftUI
import FirebaseFirestore
import AVKit
import Kingfisher

// MARK: - Project Model
struct Project: Identifiable {
    let id: String
    let userId: String
    let createdAt: Date
    let updatedAt: Date
    let editorState: [String: Any]
    let segments: [[String: Any]]
    let videoSize: VideoSize
    let finalVideoURL: String
    var thumbnailURL: String?
    
    struct VideoSize {
        let width: CGFloat
        let height: CGFloat
    }
    
    init(id: String, data: [String: Any]) {
        self.id = id
        self.userId = data["userId"] as? String ?? ""
        self.createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        self.updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
        self.editorState = data["editorState"] as? [String: Any] ?? [:]
        self.segments = data["segments"] as? [[String: Any]] ?? []
        
        if let videoSizeData = data["videoSize"] as? [String: Any] {
            self.videoSize = VideoSize(
                width: videoSizeData["width"] as? CGFloat ?? 0,
                height: videoSizeData["height"] as? CGFloat ?? 0
            )
        } else {
            self.videoSize = VideoSize(width: 0, height: 0)
        }
        
        self.finalVideoURL = data["finalVideoURL"] as? String ?? ""
        self.thumbnailURL = data["thumbnailURL"] as? String
    }
}

@MainActor
struct LibraryView: View {
    @State private var selectedFilter = 0
    @State private var showProfile = false
    @State private var projects: [Project] = []
    @StateObject private var authService = AuthenticationService()
    let filters = ["All", "In Progress", "Published"]
    
    private func fetchProjects() {
        guard let userId = authService.user?.uid else { return }
        
        let db = Firestore.firestore()
        db.collection("projects")
            .whereField("userId", isEqualTo: userId)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("❌ Error fetching projects: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                
                self.projects = documents.map { doc in
                    Project(id: doc.documentID, data: doc.data())
                }
            }
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 16) {
                // Navigation Bar
                HStack {
                    Text("Library")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: { 
                        showProfile = true
                    }) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.white.opacity(0.1))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Text(String((authService.user?.displayName?.prefix(1) ?? "U").uppercased()))
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white)
                                )
                            
                            Image(systemName: "chevron.down")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(20)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                // Filter Pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(0..<filters.count, id: \ .self) { index in
                            Button(action: {
                                withAnimation {
                                    selectedFilter = index
                                }
                            }) {
                                Text(filters[index])
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(selectedFilter == index ? .white : .white.opacity(0.6))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 20)
                                            .fill(selectedFilter == index ? Color.red : Color.white.opacity(0.1))
                                    )
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        ForEach(projects) { project in
                            ProjectCard(project: project)
                        }
                    }
                    .padding()
                }
                .onAppear {
                    fetchProjects()
                }
            }
        }
        .sheet(isPresented: $showProfile) {
            ProfileView(isPresented: $showProfile)
        }
    }
}

@MainActor
struct ProjectCard: View {
    let project: Project
    @State private var isShowingVideo = false
    @State private var videoPlayer: AVPlayer?
    
    private var thumbnailView: some View {
        ZStack {
            if let thumbnailURL = project.thumbnailURL,
               let url = URL(string: thumbnailURL) {
                KFImage(url)
                    .resizable()
                    .aspectRatio(16/9, contentMode: .fill)
            } else {
                placeholderView
            }
            
            playButton
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var placeholderView: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.white.opacity(0.1))
            .aspectRatio(16/9, contentMode: .fit)
    }
    
    private var playButton: some View {
        Button(action: {
            print("🎬 [ProjectCard] Play button tapped for project: \(project.id)")
            loadVideo()
        }) {
            Image(systemName: "play.fill")
                .font(.callout)
                .foregroundColor(.white)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            thumbnailView
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
        .sheet(isPresented: $isShowingVideo) {
            if let player = videoPlayer {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onAppear {
                        print("🎥 [ProjectCard] Video player sheet appeared")
                        print("📺 [ProjectCard] Current item duration: \(player.currentItem?.duration.seconds ?? 0) seconds")
                    }
                    .onDisappear {
                        print("🎬 [ProjectCard] Video player sheet dismissed")
                        player.pause()
                        player.replaceCurrentItem(with: nil)
                    }
            } else {
                Text("Unable to load video player")
                    .foregroundColor(.red)
            }
        }
    }
    
    private func loadVideo() {
        print("\n📼 [ProjectCard] Starting video load process")
        print("🔍 [ProjectCard] Project ID: \(project.id)")
        print("🔗 [ProjectCard] Video URL: \(project.finalVideoURL)")
        
        guard let url = URL(string: project.finalVideoURL) else {
            print("❌ [ProjectCard] Invalid video URL format")
            return
        }
        
        print("✅ [ProjectCard] URL successfully parsed: \(url)")
        
        // Create a new player with the URL
        let player = AVPlayer(url: url)
        
        // Add observer for player status
        let statusObserver = player.currentItem?.observe(\.status) { item, _ in
            switch item.status {
            case .readyToPlay:
                print("✅ [ProjectCard] Video ready to play")
                print("ℹ️ [ProjectCard] Video duration: \(item.duration.seconds) seconds")
            case .failed:
                print("❌ [ProjectCard] Video failed to load: \(item.error?.localizedDescription ?? "Unknown error")")
            case .unknown:
                print("⚠️ [ProjectCard] Video loading status unknown")
            @unknown default:
                break
            }
        }
        
        // Add observer for playback errors
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { notification in
            if let userInfo = notification.userInfo,
               let error = userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
                print("❌ [ProjectCard] Playback error: \(error.localizedDescription)")
            }
        }
        
        // Set up the player
        player.automaticallyWaitsToMinimizeStalling = true
        
        print("🎮 [ProjectCard] Player configured and ready")
        
        // Store the player and show the video
        self.videoPlayer = player
        self.isShowingVideo = true
        
        // Start playing when ready
        player.play()
        print("▶️ [ProjectCard] Play command issued")
    }
}