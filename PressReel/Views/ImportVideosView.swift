import SwiftUI
import PhotosUI
import Photos
import AVFoundation
import AVKit
import FirebaseCore
import FirebaseStorage
import FirebaseFirestore
import FirebaseAuth
import UIKit

@MainActor
class VideoImportManager: ObservableObject {
    @Published var isAuthorized = false
    @Published var selectedVideos: [ImportedVideo] = []
    @Published var isLoading = false
    @Published var uploadProgress: Double = 0
    
    private let storage = Storage.storage()
    private let db = Firestore.firestore()
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var auth = Auth.auth()
    
    init() {
        print("Initializing VideoImportManager")
        // Configure Storage settings
        storage.maxUploadRetryTime = 60
        
        // Check if user is authenticated
        if let currentUser = auth.currentUser {
            print("📱 User is authenticated: \(currentUser.uid)")
        } else {
            print("⚠️ No user is authenticated")
        }
        
        checkAuthorization()
        loadSavedVideos()
    }
    
    func checkAuthorization() {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited:
            isAuthorized = true
        case .notDetermined:
            requestAuthorization()
        default:
            isAuthorized = false
        }
    }
    
    func requestAuthorization() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            DispatchQueue.main.async {
                self?.isAuthorized = status == .authorized || status == .limited
            }
        }
    }
    
    func loadSavedVideos() {
        print("Attempting to load saved videos...")
        guard let userId = auth.currentUser?.uid else {
            print("⚠️ No authenticated user found when trying to load videos")
            return
        }
        
        print("Loading videos for user: \(userId)")
        
        db.collection("videos")
            .whereField("userId", isEqualTo: userId)
            .order(by: "dateImported", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    print("❌ Error fetching videos: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("No documents found in snapshot")
                    return
                }
                
                print("📱 Found \(documents.count) videos")
                
                self?.selectedVideos = documents.compactMap { document in
                    do {
                        let video = try document.data(as: ImportedVideo.self)
                        print("Successfully decoded video: \(video.id)")
                        return video
                    } catch {
                        print("❌ Error decoding video document: \(error.localizedDescription)")
                        return nil
                    }
                }
                
                print("📱 Successfully loaded \(self?.selectedVideos.count ?? 0) videos")
            }
    }
    
    func importVideo(from asset: PHAsset) async throws -> ImportedVideo {
        guard let userId = auth.currentUser?.uid else {
            throw NSError(domain: "VideoImport", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("Starting video import for asset: \(asset)")
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
        
        defer {
            endBackgroundTask()
        }
        
        isLoading = true
        uploadProgress = 0
        defer { 
            isLoading = false
            uploadProgress = 0
        }
        
        do {
            let fileName = UUID().uuidString
            
            // 1. Generate thumbnail first
            print("Generating thumbnail...")
            let thumbnailData = try await generateThumbnailData(from: asset)
            
            // 2. Upload thumbnail with retry
            print("Uploading thumbnail...")
            let thumbnailRef = storage.reference().child("thumbnails/\(userId)/\(fileName).jpg")
            let thumbnailMetadata = StorageMetadata()
            thumbnailMetadata.contentType = "image/jpeg"
            
            // Upload thumbnail with retry logic
            var thumbnailURL: String?
            for attempt in 1...3 {
                do {
                    _ = try await thumbnailRef.putData(thumbnailData, metadata: thumbnailMetadata)
                    // Add a small delay to allow Firebase to process the upload
                    try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                    thumbnailURL = try await thumbnailRef.downloadURL().absoluteString
                    print("Thumbnail uploaded successfully on attempt \(attempt)")
                    break
                } catch {
                    print("Thumbnail upload attempt \(attempt) failed: \(error.localizedDescription)")
                    if attempt == 3 {
                        throw error
                    }
                    try await Task.sleep(nanoseconds: 2_000_000_000) // 2 second delay before retry
                }
            }
            
            guard let finalThumbnailURL = thumbnailURL else {
                throw NSError(domain: "VideoImport", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get thumbnail URL after successful upload"])
            }
            
            // 3. Export and upload video
            print("Exporting video data...")
            let (videoData, duration) = try await exportVideoData(from: asset)
            
            print("Uploading video...")
            let videoRef = storage.reference().child("videos/\(userId)/\(fileName).mp4")
            let videoMetadata = StorageMetadata()
            videoMetadata.contentType = "video/mp4"
            
            // Upload video with progress monitoring
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let uploadTask = videoRef.putData(videoData, metadata: videoMetadata) { metadata, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    continuation.resume()
                }
                
                uploadTask.observe(.progress) { [weak self] snapshot in
                    guard let progress = snapshot.progress else { return }
                    Task { @MainActor in
                        self?.uploadProgress = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
                    }
                }
            }
            
            // Add a small delay before getting video URL
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
            let videoURL = try await videoRef.downloadURL().absoluteString
            print("Video uploaded successfully")
            
            // 4. Create and save video metadata
            print("Creating video metadata...")
            let video = ImportedVideo(
                id: UUID(),
                userId: userId,
                fileName: fileName,
                dateImported: Date(),
                duration: duration,
                storageURL: videoURL,
                thumbnailURL: finalThumbnailURL
            )
            
            print("Saving to Firestore...")
            let docRef = db.collection("videos").document(video.id.uuidString)
            try await docRef.setData(from: video)
            print("Video metadata saved to Firestore")
            
            // 5. Verify the document was saved
            let savedDoc = try await docRef.getDocument(as: ImportedVideo.self)
            print("Verified document in Firestore: \(savedDoc.id)")
            
            // 6. Verify URLs are accessible
            _ = try await URLSession.shared.data(from: URL(string: finalThumbnailURL)!)
            print("Verified thumbnail URL is accessible")
            
            // 7. Refresh the videos list
            await MainActor.run {
                loadSavedVideos()
            }
            
            return video
        } catch {
            print("Error during video import: \(error.localizedDescription)")
            // Clean up any uploaded files in case of error
            if let fileName = try? extractFileName(from: error.localizedDescription) {
                try? await cleanupFailedUpload(userId: userId, fileName: fileName)
            }
            throw error
        }
    }
    
    private func extractFileName(from errorString: String) -> String? {
        // Extract filename from error message if possible
        if let range = errorString.range(of: "Object .+/(.+?) does not exist", options: .regularExpression) {
            let match = errorString[range]
            if let fileNameRange = match.range(of: "[^/]+(?=\\.[^.]+$)", options: .regularExpression) {
                return String(match[fileNameRange])
            }
        }
        return nil
    }
    
    private func cleanupFailedUpload(userId: String, fileName: String) async throws {
        // Try to delete any uploaded files
        let videoRef = storage.reference().child("videos/\(userId)/\(fileName).mp4")
        let thumbnailRef = storage.reference().child("thumbnails/\(userId)/\(fileName).jpg")
        
        try? await videoRef.delete()
        try? await thumbnailRef.delete()
    }
    
    private func exportVideoData(from asset: PHAsset) async throws -> (Data, TimeInterval) {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.version = .current
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            
            PHImageManager.default().requestAVAsset(
                forVideo: asset,
                options: options
            ) { avAsset, _, _ in
                guard let avAsset = avAsset else {
                    continuation.resume(throwing: NSError(domain: "VideoExport", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to load video asset"]))
                    return
                }
                
                Task {
                    do {
                        let duration = try await avAsset.load(.duration).seconds
                        let data = try await self.exportToData(avAsset)
                        continuation.resume(returning: (data, duration))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    private func exportToData(_ avAsset: AVAsset) async throws -> Data {
        guard let exportSession = AVAssetExportSession(asset: avAsset, presetName: AVAssetExportPresetHighestQuality) else {
            throw NSError(domain: "VideoExport", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"])
        }
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        exportSession.outputURL = tempURL
        exportSession.outputFileType = .mp4
        
        await exportSession.export()
        
        if let error = exportSession.error {
            throw error
        }
        
        let data = try Data(contentsOf: tempURL)
        try? FileManager.default.removeItem(at: tempURL)
        return data
    }
    
    private func generateThumbnailData(from asset: PHAsset) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 320, height: 320),
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                guard let image = image,
                      let data = image.jpegData(compressionQuality: 0.8) else {
                    continuation.resume(throwing: NSError(domain: "ThumbnailGeneration", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to generate thumbnail"]))
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }
    
    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
    
    func deleteVideo(_ video: ImportedVideo) {
        guard auth.currentUser?.uid == video.userId else {
            print("User not authorized to delete this video")
            return
        }
        
        // Start background task for deletion
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
        
        Task {
            do {
                // Delete from Storage
                let videoRef = storage.reference(forURL: video.storageURL)
                try await videoRef.delete()
                
                let thumbnailRef = storage.reference(forURL: video.thumbnailURL)
                try await thumbnailRef.delete()
                
                // Delete from Firestore
                try await db.collection("videos").document(video.id.uuidString).delete()
            } catch {
                print("Error deleting video: \(error)")
            }
            
            await MainActor.run {
                endBackgroundTask()
            }
        }
    }
}

struct ImportedVideo: Identifiable, Codable {
    let id: UUID
    let userId: String
    let fileName: String
    let dateImported: Date
    let duration: TimeInterval
    let storageURL: String
    let thumbnailURL: String
    
    enum CodingKeys: String, CodingKey {
        case id, userId, fileName, dateImported, duration, storageURL, thumbnailURL
    }
}

struct VideoThumbnail: View {
    let video: ImportedVideo
    @State private var thumbnail: UIImage?
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            } else if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "video")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding()
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .overlay(
            Text(formatDuration(video.duration))
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.7))
                .cornerRadius(4)
                .padding(4),
            alignment: .bottomTrailing
        )
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        guard let url = URL(string: video.thumbnailURL) else { return }
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = UIImage(data: data) {
                    await MainActor.run {
                        self.thumbnail = image
                        self.isLoading = false
                    }
                }
            } catch {
                print("Error loading thumbnail: \(error)")
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct ImportVideosView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var importManager = VideoImportManager()
    @State private var showingPhotoPicker = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isSelectionMode = false
    @State private var selectedVideos = Set<UUID>()
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 0) {
                        // Top separator line
                        Color.white.opacity(0.1)
                            .frame(height: 0.5)
                            .padding(.top, 0)
                        
                        if importManager.isLoading {
                            UploadProgressView(progress: importManager.uploadProgress)
                        } else {
                            VideoGridView(
                                videos: importManager.selectedVideos,
                                importManager: importManager,
                                isSelectionMode: $isSelectionMode,
                                selectedVideos: $selectedVideos
                            )
                            .padding(.top, 16)
                            .onAppear {
                                print("VideoGridView appeared, refreshing videos")
                                importManager.loadSavedVideos()
                            }
                        }
                    }
                }
                .refreshable {
                    print("Manual refresh triggered")
                    importManager.loadSavedVideos()
                }
                
                // Bottom Bar
                if isSelectionMode {
                    VStack {
                        Spacer()
                        HStack {
                            Button(action: {
                                isSelectionMode = false
                                selectedVideos.removeAll()
                            }) {
                                Text("Cancel")
                                    .font(.system(size: 17))
                                    .foregroundColor(.white)
                            }
                            
                            Spacer()
                            
                            if !selectedVideos.isEmpty {
                                Button(action: {
                                    // Handle next action
                                }) {
                                    Text("Next")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(
                            Rectangle()
                                .fill(Color.black)
                                .edgesIgnoringSafeArea(.bottom)
                                .shadow(color: .black.opacity(0.2), radius: 10, y: -5)
                        )
                    }
                }
            }
            .navigationTitle("Your Videos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !isSelectionMode {
                        Button(action: { dismiss() }) {
                            Text("Done")
                                .font(.system(size: 17, weight: .regular))
                                .foregroundColor(.white)
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !isSelectionMode {
                        HStack {
                            Button(action: { isSelectionMode = true }) {
                                Text("Select")
                                    .font(.system(size: 17))
                                    .foregroundColor(.red)
                            }
                            
                            Button(action: { showingPhotoPicker = true }) {
                                Image(systemName: "plus")
                                    .foregroundColor(.red)
                                    .font(.system(size: 17, weight: .semibold))
                            }
                        }
                    }
                }
            }
            .photosPicker(
                isPresented: $showingPhotoPicker,
                selection: .init(get: { [] }, set: { items in
                    handlePhotoSelection(items)
                }),
                maxSelectionCount: 5,
                matching: .videos,
                photoLibrary: .shared()
            )
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func handlePhotoSelection(_ items: [PhotosPickerItem]) {
        Task {
            do {
                for item in items {
                    if let identifier = item.itemIdentifier,
                       let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject {
                        print("Processing selected video with identifier: \(identifier)")
                        try await importManager.importVideo(from: asset)
                    }
                }
            } catch {
                print("Error handling selection: \(error.localizedDescription)")
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
}

struct UploadProgressView: View {
    let progress: Double
    
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)
            
            Text("Uploading Video...")
                .font(.headline)
                .foregroundColor(.white)
            
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .frame(width: 200)
                .tint(.red)
            
            Text("\(Int(progress * 100))%")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }
}

struct EmptyStateView: View {
    @Binding var showingPhotoPicker: Bool
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "video.badge.plus")
                .font(.system(size: 44))
                .foregroundColor(.red)
                .frame(width: 80, height: 80)
                .background(Color.white.opacity(0.05))
                .clipShape(Circle())
            
            VStack(spacing: 8) {
                Text("No Videos Yet")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("Import videos from your library to get started")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            
            Button(action: { showingPhotoPicker = true }) {
                Text("Import Videos")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 200, height: 54)
                    .background(Color.red)
                    .cornerRadius(16)
            }
        }
        .padding(.vertical, 60)
    }
}

struct VideoGridView: View {
    let videos: [ImportedVideo]
    let importManager: VideoImportManager
    @State private var selectedVideo: ImportedVideo?
    @State private var isShowingVideoPlayer = false
    @Binding var isSelectionMode: Bool
    @Binding var selectedVideos: Set<UUID>
    
    let columns = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1)
    ]
    
    var body: some View {
        Group {
            if videos.isEmpty {
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    Text("Loading your videos...")
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LazyVGrid(columns: columns, spacing: 1) {
                    ForEach(videos) { video in
                        ZStack(alignment: .topLeading) {
                            VideoThumbnail(video: video)
                                .frame(height: (UIScreen.main.bounds.width / 4) - 0.75)
                                .onTapGesture {
                                    if isSelectionMode {
                                        if selectedVideos.contains(video.id) {
                                            selectedVideos.remove(video.id)
                                        } else {
                                            selectedVideos.insert(video.id)
                                        }
                                    } else {
                                        selectedVideo = video
                                        isShowingVideoPlayer = true
                                    }
                                }
                            
                            if isSelectionMode {
                                ZStack {
                                    Circle()
                                        .strokeBorder(Color.white, lineWidth: 2)
                                        .background(
                                            Circle()
                                                .fill(selectedVideos.contains(video.id) ? Color.red : Color.clear)
                                        )
                                        .frame(width: 24, height: 24)
                                    
                                    if selectedVideos.contains(video.id) {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                                .padding(8)
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                importManager.deleteVideo(video)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 0)
            }
        }
        .sheet(isPresented: $isShowingVideoPlayer) {
            if let video = selectedVideo {
                VideoPlayerView(video: video)
            }
        }
    }
}

struct VideoPlayerView: View {
    let video: ImportedVideo
    @Environment(\.dismiss) var dismiss
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                if let player = player {
                    VideoPlayer(player: player)
                        .edgesIgnoringSafeArea(.all)
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        player?.pause()
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        if isPlaying {
                            player?.pause()
                        } else {
                            player?.play()
                        }
                        isPlaying.toggle()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
    
    private func setupPlayer() {
        guard let url = URL(string: video.storageURL) else { return }
        let player = AVPlayer(url: url)
        self.player = player
        
        // Add observer for playback end
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }
        
        // Start playing automatically
        player.play()
        isPlaying = true
    }
} 