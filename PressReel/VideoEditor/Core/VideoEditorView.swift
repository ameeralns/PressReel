import SwiftUI
import VideoEditorSDK
import Photos
import UIKit
import AVFoundation
import FirebaseStorage
import FirebaseAuth
import FirebaseFirestore

struct VideoEditorView: View {
    // MARK: - Helper Functions
    
    private func formatTime(seconds: Float64) -> String {
        let time = Int(seconds)
        let hours = time / 3600
        let minutes = (time % 3600) / 60
        let seconds = time % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    private func generateThumbnail(from videoURL: URL) -> UIImage? {
        let asset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        do {
            let cgImage = try imageGenerator.copyCGImage(at: .zero, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            print("❌ [VideoEditor] Failed to generate thumbnail: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Properties
    let asset: PHAsset
    let onComplete: (URL?) -> Void
    @Environment(\.presentationMode) var presentationMode
    
    // MARK: - Initialization
    init(asset: PHAsset, onComplete: @escaping (URL?) -> Void) {
        self.asset = asset
        self.onComplete = onComplete
    }
    
    // MARK: - Helper Methods
    private func dismissAll() {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController,
           let presentedVC = rootVC.presentedViewController {
            presentedVC.dismiss(animated: true) {
                DispatchQueue.main.async {
                    self.presentationMode.wrappedValue.dismiss()
                }
            }
        }
    }
    
    // MARK: - Body
    var body: some View {
        Color.clear.onAppear {
            // Request video asset
            PHImageManager.default().requestAVAsset(forVideo: asset, options: nil) { avAsset, _, _ in
                guard let avAsset = avAsset else {
                    print("❌ [VideoEditor] Failed to get video asset")
                    onComplete(nil)
                    presentationMode.wrappedValue.dismiss()
                    return
                }
                
                // Execute on main thread since we're updating UI
                DispatchQueue.main.async {
                    // Create video editor configuration
                    let configuration = Configuration { builder in
                        // Configure overlay tool
                        builder.configureOverlayToolController { options in
                            options.initialOverlayIntensity = 0.5
                            options.showOverlayIntensitySlider = false
                        }
                        builder.theme = .dynamic
                        
                        // Configure icons
                        setupCustomIcons()
                    }
                    
                    // Create video editor
                    let video = Video(asset: avAsset)
                    let videoEditor = VideoEditor(video: video, configuration: configuration)
                        .onDidSave { result in
                            print("📹 [VideoEditor] Save completed")
                            
                            // Check if user is authenticated
                            guard let currentUser = Auth.auth().currentUser else {
                                print("❌ [VideoEditor] No authenticated user found")
                                onComplete(nil)
                                dismissAll()
                                return
                            }
                            
                            // Create VideoEditViewController to get serialized settings
                            let videoEditViewController = VideoEditViewController(videoAsset: result.task.video)
                            
                            // Get serialized settings (optional Data object)
                            guard let serializedSettings = videoEditViewController.serializedSettings else {
                                print("❌ [VideoEditor] Failed to get serialized settings")
                                return
                            }
                            
                            // Convert to JSON for Firestore
                            guard let jsonDict = try? JSONSerialization.jsonObject(with: serializedSettings, options: []) as? [String: Any] else {
                                print("❌ [VideoEditor] Failed to convert serialized settings to JSON")
                                return
                            }
                            
                            // Create project data
                            let timestamp = Int(Date().timeIntervalSince1970)
                            let projectId = "\(currentUser.uid)_\(timestamp)"
                            
                            // Prepare video segments data
                            let uploadManager = VideoUploadManager()
                            let uploadGroup = DispatchGroup()
                            let segmentsQueue = DispatchQueue(label: "com.pressreel.segments")
                            var segmentsData: [[String: Any]] = []
                            
                            for (index, segment) in result.task.video.segments.enumerated() {
                                uploadGroup.enter()
                                
                                Task {
                                    do {
                                        let metadata = StorageMetadata()
                                        metadata.contentType = "video/mp4"
                                        
                                        let path = "users/\(currentUser.uid)/projects/\(projectId)/segments/\(index).mp4"
                                        let downloadURL = try await uploadManager.uploadVideo(
                                            at: segment.url,
                                            to: path,
                                            metadata: metadata
                                        )
                                        
                                        // Get segment duration and time values
                                        let asset = AVAsset(url: segment.url)
                                        let duration = Float64(CMTimeGetSeconds(asset.duration))
                                        
                                        // Create segment data with proper time values
                                        let segmentData: [String: Any] = [
                                            "index": index,
                                            "url": downloadURL.absoluteString,
                                            "duration": duration,
                                            "durationFormatted": formatTime(seconds: duration)
                                        ]
                                        
                                        segmentsQueue.async {
                                            segmentsData.append(segmentData)
                                            print("📹 [VideoEditor] Successfully uploaded segment \(index)")
                                        }
                                    } catch {
                                        print("❌ [VideoEditor] Failed to upload segment \(index): \(error.localizedDescription)")
                                    }
                                    
                                    uploadGroup.leave()
                                }
                            }
                            
                            uploadGroup.notify(queue: .main) {
                                // Generate and upload thumbnail
                                if let thumbnailImage = generateThumbnail(from: result.output.url),
                                   let thumbnailData = thumbnailImage.jpegData(compressionQuality: 0.7) {
                                    
                                    let thumbnailRef = Storage.storage().reference()
                                        .child("users/\(currentUser.uid)/projects/\(projectId)/thumbnail.jpg")
                                    
                                    thumbnailRef.putData(thumbnailData, metadata: nil) { metadata, error in
                                        if let error = error {
                                            print("❌ [VideoEditor] Failed to upload thumbnail: \(error.localizedDescription)")
                                            return
                                        }
                                        
                                        // Get thumbnail URL
                                        thumbnailRef.downloadURL { url, error in
                                            if let thumbnailURL = url?.absoluteString {
                                                // Create project document with thumbnail and final video URL
                                                let projectData: [String: Any] = [
                                                    "userId": currentUser.uid,
                                                    "createdAt": timestamp,
                                                    "updatedAt": timestamp,
                                                    "editorState": jsonDict,
                                                    "segments": segmentsData,
                                                    "videoSize": [
                                                        "width": result.task.video.size.width,
                                                        "height": result.task.video.size.height
                                                    ],
                                                    "thumbnailURL": thumbnailURL,
                                                    "finalVideoURL": result.output.url.absoluteString
                                                ]
                                                
                                                // Save to Firestore
                                                let db = Firestore.firestore()
                                                db.collection("projects").document(projectId).setData(projectData) { error in
                                                    if let error = error {
                                                        print("❌ [VideoEditor] Failed to save project: \(error.localizedDescription)")
                                                    } else {
                                                        print("📹 [VideoEditor] Project saved successfully with thumbnail")
                                                    }
                                                }
                                            }
                                        }
                                    }
                                } else {
                                    print("❌ [VideoEditor] Failed to generate thumbnail")
                                    
                                    // Save project without thumbnail but with final video URL
                                    let projectData: [String: Any] = [
                                        "userId": currentUser.uid,
                                        "createdAt": timestamp,
                                        "updatedAt": timestamp,
                                        "editorState": jsonDict,
                                        "segments": segmentsData,
                                        "videoSize": [
                                            "width": result.task.video.size.width,
                                            "height": result.task.video.size.height
                                        ],
                                        "finalVideoURL": result.output.url.absoluteString
                                    ]
                                    
                                    // Save to Firestore
                                    let db = Firestore.firestore()
                                    db.collection("projects").document(projectId).setData(projectData) { error in
                                        if let error = error {
                                            print("❌ [VideoEditor] Failed to save project: \(error.localizedDescription)")
                                        } else {
                                            print("📹 [VideoEditor] Project saved successfully without thumbnail")
                                        }
                                    }
                                }
                            }
                            
                            // Generate and upload thumbnail
                            if let thumbnailImage = generateThumbnail(from: result.output.url) {
                                if let thumbnailData = thumbnailImage.jpegData(compressionQuality: 0.7) {
                                    let thumbnailRef = Storage.storage().reference()
                                        .child("users/\(currentUser.uid)/thumbnails/\(projectId).jpg")
                                    
                                    thumbnailRef.putData(thumbnailData, metadata: nil) { metadata, error in
                                        if let error = error {
                                            print("❌ [VideoEditor] Failed to upload thumbnail: \(error.localizedDescription)")
                                        }
                                    }
                                }
                            }
                            
                            // Upload final exported video
                            let videoRef = Storage.storage().reference()
                                .child("users/\(currentUser.uid)/projects/\(projectId)/final.mp4")
                            
                            // Create metadata with content type
                            let metadata = StorageMetadata()
                            metadata.contentType = "video/mp4"
                            
                            // Configure background upload session
                            let config = URLSessionConfiguration.background(withIdentifier: "com.pressreel.upload.final")
                            config.isDiscretionary = true
                            config.sessionSendsLaunchEvents = true
                            
                            videoRef.putFile(from: result.output.url, metadata: metadata) { metadata, error in
                                DispatchQueue.main.async {
                                    if let error = error {
                                        print("❌ [VideoEditor] Failed to upload final video: \(error.localizedDescription)")
                                    } else {
                                        print("📹 [VideoEditor] Final video uploaded")
                                        videoRef.downloadURL { url, error in
                                            if let downloadURL = url {
                                                print("📹 [VideoEditor] Final video URL: \(downloadURL.absoluteString)")
                                                // Update project with final video URL
                                                let db = Firestore.firestore()
                                                db.collection("projects").document(projectId).updateData([
                                                    "finalVideoUrl": downloadURL.absoluteString
                                                ])
                                            }
                                            onComplete(result.output.url)
                                            dismissAll()
                                        }
                                    }
                                }
                            }
                        }
                        .onDidCancel {
                            print("🚫 [VideoEditor] Cancelled")
                            onComplete(nil)
                            dismissAll()
                        }
                        .onDidFail { error in
                            print("❌ [VideoEditor] Failed: \(error.localizedDescription)")
                            onComplete(nil)
                            dismissAll()
                        }
                        .ignoresSafeArea()
                    
                    // Present the editor
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = windowScene.windows.first,
                       let viewController = window.rootViewController {
                        let hostingController = UIHostingController(rootView: videoEditor)
                        hostingController.modalPresentationStyle = .fullScreen
                        viewController.present(hostingController, animated: true)
                    }
                }
            }
        }
    }
}

// MARK: - Helper Functions
private func setupCustomIcons() {
    let config = UIImage.SymbolConfiguration(scale: .large)
    
    IMGLY.bundleImageBlock = { imageName in
        switch imageName {
        case "imgly_icon_cancel_44pt":
            return UIImage(systemName: "multiply.circle.fill", withConfiguration: config)?.icon(pt: 44, alpha: 0.6)
        case "imgly_icon_approve_44pt":
            return UIImage(systemName: "checkmark.circle.fill", withConfiguration: config)?.icon(pt: 44, alpha: 0.6)
        case "imgly_icon_save":
            return UIImage(systemName: "arrow.up.circle.fill", withConfiguration: config)?.icon(pt: 44, alpha: 0.6)
        case "imgly_icon_undo_48pt":
            return UIImage(systemName: "arrow.uturn.backward", withConfiguration: config)?.icon(pt: 48)
        case "imgly_icon_redo_48pt":
            return UIImage(systemName: "arrow.uturn.forward", withConfiguration: config)?.icon(pt: 48)
        case "imgly_icon_play_48pt":
            return UIImage(systemName: "play.fill", withConfiguration: config)?.icon(pt: 48)
        case "imgly_icon_pause_48pt":
            return UIImage(systemName: "pause.fill", withConfiguration: config)?.icon(pt: 48)
        case "imgly_icon_sound_on_48pt":
            return UIImage(systemName: "speaker.wave.2.fill", withConfiguration: config)?.icon(pt: 48)
        case "imgly_icon_sound_off_48pt":
            return UIImage(systemName: "speaker.slash.fill", withConfiguration: config)?.icon(pt: 48)
        default:
            return nil
        }
    }
}

// MARK: - Helper Extensions
private extension UIImage {
    func icon(pt: CGFloat, alpha: CGFloat = 1) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(CGSize(width: pt, height: pt), false, scale)
        let position = CGPoint(x: (pt - size.width) / 2, y: (pt - size.height) / 2)
        draw(at: position, blendMode: .normal, alpha: alpha)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage
    }
}
