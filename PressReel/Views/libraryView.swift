import SwiftUI
import FirebaseFirestore
import AVKit
import Kingfisher
import FirebaseStorage

// MARK: - Project Model
struct Project: Identifiable {
    let id: String
    let userId: String
    let title: String
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
        self.title = data["title"] as? String ?? "Untitled Project"
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
class LibraryViewModel: ObservableObject {
    @Published var projects: [Project] = []
    private var listener: ListenerRegistration? {
        willSet {
            listener?.remove()
        }
    }
    
    func startListening(userId: String) {
        let db = Firestore.firestore()
        listener = db.collection("projects")
            .whereField("userId", isEqualTo: userId)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    
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
    }
    
    deinit {
        // The willSet observer will handle cleanup
        listener = nil
    }
}

@MainActor
struct LibraryView: View {
    @State private var selectedFilter = 0
    @State private var showProfile = false
    @StateObject private var viewModel = LibraryViewModel()
    @StateObject private var authService = AuthenticationService()
    let filters = ["All", "In Progress", "Published"]
    
    private func setupProjectsListener() {
        guard let userId = authService.user?.uid else { return }
        viewModel.startListening(userId: userId)
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
                        ForEach(viewModel.projects) { project in
                            ProjectCard(project: project, onUpdate: {})
                        }
                    }
                    .padding()
                }
                .onAppear {
                    setupProjectsListener()
                }
            }
        }
        .sheet(isPresented: $showProfile) {
            ProfileView(isPresented: $showProfile)
        }
    }
}

@MainActor
class VideoPlayerViewModel: ObservableObject {
    @Published var isVideoReady = false
    @Published var player: AVPlayer?
    @Published var error: Error?
    private var statusObserver: NSKeyValueObservation?
    
    func loadVideo(url: URL) async {
        cleanup() // Clean up any existing player
        isVideoReady = false
        error = nil
        
        print("🎥 [ProjectCard] Creating player with URL: \(url)")
        
        // Create an AVAsset and load its properties
        let asset = AVURLAsset(url: url)
        print("📼 [ProjectCard] Loading asset properties...")
        
        do {
            // Load duration and tracks properties asynchronously
            let duration = try await asset.load(.duration)
            print("ℹ️ [ProjectCard] Asset duration: \(duration.seconds) seconds")
            
            // Create a player item with the loaded asset
            let playerItem = AVPlayerItem(asset: asset)
            print("🎥 [ProjectCard] Created player item")
            
            // Create the player with the item
            let newPlayer = AVPlayer(playerItem: playerItem)
            newPlayer.automaticallyWaitsToMinimizeStalling = true
            
            // Set up status observation before assigning to published property
            statusObserver = playerItem.observe(\AVPlayerItem.status) { [weak self] item, _ in
                guard let self = self else { return }
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    print("📺 [ProjectCard] Player item status changed: \(item.status.rawValue)")
                    
                    switch item.status {
                    case .readyToPlay:
                        print("✅ [ProjectCard] Video ready to play")
                        self.isVideoReady = true
                        self.player?.play()
                    case .failed:
                        let errorMessage = item.error?.localizedDescription ?? "Unknown error"
                        print("❌ [ProjectCard] Video failed to load: \(errorMessage)")
                        self.error = item.error ?? NSError(domain: "VideoPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMessage])
                        self.cleanup()
                    case .unknown:
                        print("⚠️ [ProjectCard] Video loading status unknown")
                    @unknown default:
                        break
                    }
                }
            }
            
            // Set up notification for playback errors
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime,
                object: playerItem,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if let userInfo = notification.userInfo,
                       let error = userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
                        print("❌ [ProjectCard] Playback error: \(error.localizedDescription)")
                        self.error = error
                        self.cleanup()
                    }
                }
            }
            
            // Finally, assign the player
            print("🎮 [ProjectCard] Setting up player")
            self.player = newPlayer
            
        } catch {
            print("❌ [ProjectCard] Failed to load asset: \(error.localizedDescription)")
            self.error = error
            self.cleanup()
        }
    }
    
    nonisolated func cleanup() {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.statusObserver?.invalidate()
            self.statusObserver = nil
            self.player?.pause()
            self.player?.replaceCurrentItem(with: nil)
            self.player = nil
            self.isVideoReady = false
        }
    }
    
    deinit {
        cleanup()
    }
}

struct ProjectCard: View {
    let project: Project
    let onUpdate: () -> Void
    @State private var isShowingVideo = false
    @State private var isEditingTitle = false
    @State private var editedTitle: String = ""
    @State private var isDeleting = false
    @State private var isExporting = false
    @StateObject private var videoPlayerViewModel = VideoPlayerViewModel()
    @Environment(\.presentationMode) var presentationMode
    
    private func updateProjectTitle(newTitle: String) {
        guard !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let db = Firestore.firestore()
        db.collection("projects").document(project.id).updateData([
            "title": newTitle,
            "updatedAt": Timestamp(date: Date())
        ]) { error in
            if let error = error {
                print("❌ Error updating project title: \(error.localizedDescription)")
            } else {
                print("✅ Project title updated successfully")
                onUpdate()
            }
        }
    }
    
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
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func deleteProject() async {
        isDeleting = true
        let db = Firestore.firestore()
        let storage = Storage.storage()
        
        do {
            let userId = project.userId
            
            // Delete all segment files from Storage
            for segment in project.segments {
                if let url = segment["url"] as? String,
                   let videoURL = URL(string: url) {
                    let path = videoURL.lastPathComponent
                    let reference = storage.reference().child("segments/\(userId)/\(path)")
                    do {
                        try await reference.delete()
                    } catch {
                        print("⚠️ Skipping non-existent segment file: \(path)")
                        continue
                    }
                }
            }
            
            // Delete thumbnail if exists
            if let thumbnailURL = project.thumbnailURL,
               let url = URL(string: thumbnailURL) {
                let path = url.lastPathComponent
                let reference = storage.reference().child("thumbnails/\(userId)/\(path)")
                do {
                    try await reference.delete()
                } catch {
                    print("⚠️ Skipping non-existent thumbnail: \(path)")
                }
            }
            
            // Delete final video if exists
            if !project.finalVideoURL.isEmpty,
               let url = URL(string: project.finalVideoURL) {
                let path = url.lastPathComponent
                let reference = storage.reference().child("videos/\(userId)/\(path)")
                do {
                    try await reference.delete()
                } catch {
                    print("⚠️ Skipping non-existent video: \(path)")
                }
            }
            
            // Delete the project document from Firestore
            try await db.collection("projects").document(project.id).delete()
            
            print("✅ Project and associated files deleted successfully")
            onUpdate()
        } catch {
            print("❌ Error deleting project: \(error.localizedDescription)")
        }
        
        isDeleting = false
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            thumbnailView
            
            VStack(alignment: .leading, spacing: 4) {
                Group {
                    if isEditingTitle {
                        TextField("Project Title", text: $editedTitle, onCommit: {
                            isEditingTitle = false
                            if editedTitle != project.title {
                                updateProjectTitle(newTitle: editedTitle)
                            }
                        })
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.callout)
                        .foregroundColor(.black)
                    } else {
                        Text(project.title)
                            .font(.callout)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .onTapGesture {
                                editedTitle = project.title
                                isEditingTitle = true
                            }
                    }
                }
                
                Text("Created \(formattedDate(project.createdAt))")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            Button(action: {
                Task {
                    await exportVideo()
                }
            }) {
                Label("Export Video", systemImage: "square.and.arrow.up")
            }
            
            Button(role: .destructive, action: {
                Task {
                    await deleteProject()
                }
            }) {
                Label("Delete Project", systemImage: "trash")
            }
        }
        .overlay {
            if isDeleting {
                ZStack {
                    Color.black.opacity(0.7)
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
            }
        }
        .sheet(isPresented: $isShowingVideo) {
            GeometryReader { geometry in
                ZStack {
                    Color.black.edgesIgnoringSafeArea(.all)
                    
                    if let error = videoPlayerViewModel.error {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 40))
                        Text(error.localizedDescription)
                            .foregroundColor(.red)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else if let player = videoPlayerViewModel.player {
                    if videoPlayerViewModel.isVideoReady {
                        VideoPlayer(player: player)
                            .ignoresSafeArea()
                            .onDisappear {
                                print("🎥 [ProjectCard] Video player sheet dismissed")
                                Task { @MainActor in
                                    videoPlayerViewModel.cleanup()
                                }
                            }
                    } else {
                        VStack(spacing: 20) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .red))
                                .scaleEffect(2.0)
                            
                            Text("Preparing video...")
                                .foregroundColor(.white)
                                .font(.headline)
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                } else {
                    VStack(spacing: 20) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .red))
                            .scaleEffect(2.0)
                        
                        Text("Loading video...")
                            .foregroundColor(.white)
                            .font(.headline)
                    }
                }
                }
            }
        }
    }
    
    private func exportVideo() async {
        guard let videoURL = URL(string: project.finalVideoURL) else { return }
        
        let storage = Storage.storage()
        let reference = storage.reference(forURL: videoURL.absoluteString)
        
        do {
            // Get the temporary local URL for the video
            let localURL = FileManager.default.temporaryDirectory.appendingPathComponent(videoURL.lastPathComponent)
            _ = try await reference.writeAsync(toFile: localURL)
            
            // Share the video using UIActivityViewController
            await MainActor.run {
                let activityVC = UIActivityViewController(activityItems: [localURL], applicationActivities: nil)
                
                // Present the share sheet
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first,
                   let rootViewController = window.rootViewController {
                    rootViewController.present(activityVC, animated: true)
                }
            }
        } catch {
            print("❌ Error exporting video: \(error.localizedDescription)")
        }
    }
    
    private func loadVideo() {
        print("📼 [ProjectCard] Starting video load process")
        print("🔍 [ProjectCard] Project ID: \(project.id)")
        print("🔗 [ProjectCard] Video URL: \(project.finalVideoURL)")
        
        guard let url = URL(string: project.finalVideoURL) else {
            print("❌ [ProjectCard] Invalid video URL format")
            return
        }
        
        print("✅ [ProjectCard] URL successfully parsed: \(url)")
        
        Task {
            await videoPlayerViewModel.loadVideo(url: url)
        }
        isShowingVideo = true
    }
}