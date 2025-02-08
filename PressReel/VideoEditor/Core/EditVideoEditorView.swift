import SwiftUI
import VideoEditorSDK
import Photos
import UIKit
import AVFoundation
import FirebaseStorage
import FirebaseAuth
import FirebaseFirestore

struct EditVideoEditorView: UIViewControllerRepresentable {
    // MARK: - Properties
    let project: Project
    let onComplete: (URL?) -> Void
    @Environment(\.presentationMode) var presentationMode
    
    // MARK: - Initialization
    init(project: Project, onComplete: @escaping (URL?) -> Void) {
        self.project = project
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
    
    // MARK: - UIViewControllerRepresentable
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIViewController(context: Context) -> VideoEditViewController {
        print("🎬 [EditVideoEditor] Starting to create editor for project: \(project.id)")
        print("📊 [EditVideoEditor] Project details:")
        print("   - Title: \(project.title)")
        print("   - Created: \(project.createdAt)")
        print("   - Updated: \(project.updatedAt)")
        print("   - Video Size: \(project.videoSize.width)x\(project.videoSize.height)")
        print("   - Number of segments: \(project.segments.count)")
        
        guard let videoURL = URL(string: project.finalVideoURL) else {
            print("❌ [EditVideoEditor] Failed to create URL from: \(project.finalVideoURL)")
            fatalError("Invalid video URL")
        }
        
        print("🎥 [EditVideoEditor] Video URL created: \(videoURL.absoluteString)")
            

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
                
                print("🎥 [EditVideoEditor] Starting to create video segments")
                
                // Sort segments by index
                let sortedSegments = project.segments.sorted { 
                    ($0["index"] as? Int ?? 0) < ($1["index"] as? Int ?? 0)
                }
                
                print("🔀 [EditVideoEditor] Processing \(sortedSegments.count) segments in order")
                
                // Calculate time ranges based on segment order and durations
                var currentStartTime: Double = 0.0
                let segments = sortedSegments.compactMap { segmentData -> VideoSegment? in
                    guard let segmentURL = segmentData["url"] as? String,
                          let url = URL(string: segmentURL),
                          let duration = segmentData["duration"] as? Double,
                          let index = segmentData["index"] as? Int else {
                        print("⚠️ [EditVideoEditor] Invalid segment data: \(segmentData)")
                        return nil
                    }
                    
                    let endTime = currentStartTime + duration
                    print("✂️ [EditVideoEditor] Creating segment \(index):")
                    print("   - URL: \(url.lastPathComponent)")
                    print("   - Start time: \(currentStartTime)")
                    print("   - End time: \(endTime)")
                    print("   - Duration: \(duration)")
                    
                    let segment = VideoSegment(url: url, startTime: currentStartTime, endTime: endTime)
                    currentStartTime = endTime
                    return segment
                }
                
                print("✅ [EditVideoEditor] Successfully created \(segments.count) segments with calculated time ranges")
                
                // Create video with segments and size
                let video = Video(
                    segments: segments,
                    size: CGSize(width: project.videoSize.width, height: project.videoSize.height)
                )
                
                var videoEditViewController: VideoEditViewController
                
                print("🔄 [EditVideoEditor] Checking for saved editor state...")
                if !project.editorState.isEmpty {
                    print("📝 [EditVideoEditor] Found existing editor state")
                    do {
                        let jsonData = try JSONSerialization.data(withJSONObject: project.editorState)
                        
                        print("🔄 [EditVideoEditor] Attempting to deserialize editor state...")
                        if let deserializationResult = try? Deserializer.deserialize(
                            data: jsonData,
                            imageDimensions: CGSize(width: project.videoSize.width, height: project.videoSize.height),
                            assetCatalog: configuration.assetCatalog
                        ),
                           let photoEditModel = deserializationResult.model {
                            print("✅ [EditVideoEditor] Successfully deserialized editor state")
                            print("🎨 [EditVideoEditor] Creating editor with restored state...")
                            videoEditViewController = VideoEditViewController(
                                videoAsset: video,
                                configuration: configuration,
                                photoEditModel: photoEditModel
                            )
                            print("✅ [EditVideoEditor] Editor created with restored state")
                        } else {
                            print("⚠️ [EditVideoEditor] Deserialization failed, creating new editor")
                            videoEditViewController = VideoEditViewController(
                                videoAsset: video,
                                configuration: configuration
                            )
                            print("✅ [EditVideoEditor] Created new editor as fallback")
                        }
                    } catch {
                        print("❌ [VideoEditor] Failed to restore editor state: \(error.localizedDescription)")
                        // Fallback to new editor if deserialization fails
                        videoEditViewController = VideoEditViewController(
                            videoAsset: video,
                            configuration: configuration
                        )
                    }
                } else {
                    // Create new editor if no state exists
                    videoEditViewController = VideoEditViewController(
                        videoAsset: video,
                        configuration: configuration
                    )
                }
                
                videoEditViewController.modalPresentationStyle = .fullScreen
                videoEditViewController.delegate = context.coordinator
                return videoEditViewController
    }
    
    func updateUIViewController(_ uiViewController: VideoEditViewController, context: Context) {
        // No updates needed
    }
    
    // MARK: - Coordinator
    class Coordinator: NSObject, VideoEditViewControllerDelegate {
        var parent: EditVideoEditorView
        
        init(_ parent: EditVideoEditorView) {
            self.parent = parent
        }
        
        func videoEditViewControllerShouldStart(_ videoEditViewController: VideoEditViewController, task: VideoEditorTask) -> Bool {
            print("📣 [EditVideoEditor] Starting editor task")
            print("   - Video segments: \(task.video.segments.count)")
            print("   - Video size: \(task.video.size.width)x\(task.video.size.height)")
            return true
        }
        
        func videoEditViewControllerDidFinish(_ videoEditViewController: VideoEditViewController, result: VideoEditorResult) {
            print("🎥 [EditVideoEditor] Save completed")
            print("💾 [EditVideoEditor] Output details:")
            print("   - Output URL: \(result.output.url)")
            print("   - Video segments: \(result.task.video.segments.count)")
            print("   - Has editor state: \(videoEditViewController.serializedSettings != nil)")
            
            // Check if user is authenticated
            guard let currentUser = Auth.auth().currentUser else {
                print("❌ [VideoEditor] No authenticated user found")
                self.parent.onComplete(nil)
                videoEditViewController.dismiss(animated: true)
                return
            }
            
            // Get serialized settings
            guard let serializedSettings = videoEditViewController.serializedSettings else {
                print("❌ [VideoEditor] Failed to get serialized settings")
                self.parent.onComplete(nil)
                videoEditViewController.dismiss(animated: true)
                return
            }
            
            // Convert to JSON for Firestore
            guard let jsonDict = try? JSONSerialization.jsonObject(with: serializedSettings, options: []) as? [String: Any] else {
                print("❌ [VideoEditor] Failed to convert serialized settings to JSON")
                self.parent.onComplete(nil)
                videoEditViewController.dismiss(animated: true)
                return
            }
            
            // Create segments data
            let segmentsData = result.task.video.segments.map { segment in
                return [
                    "startTime": segment.startTime,
                    "endTime": segment.endTime
                ]
            }
            
            let timestamp = Timestamp(date: Date())
            
            // Create storage reference for video
            let storage = Storage.storage()
            let videoRef = storage.reference().child("users/\(currentUser.uid)/projects/\(self.parent.project.id)/final.mp4")
            
            // Create metadata
            let metadata = StorageMetadata()
            metadata.contentType = "video/mp4"
            
            // Upload video
            videoRef.putFile(from: result.output.url, metadata: metadata) { metadata, error in
                if let error = error {
                    print("❌ [VideoEditor] Failed to upload video: \(error.localizedDescription)")
                    self.parent.onComplete(nil)
                    videoEditViewController.dismiss(animated: true)
                    return
                }
                
                // Get download URL
                videoRef.downloadURL { url, error in
                    guard let downloadURL = url else {
                        print("❌ [VideoEditor] Failed to get download URL: \(error?.localizedDescription ?? "Unknown error")")
                        self.parent.onComplete(nil)
                        videoEditViewController.dismiss(animated: true)
                        return
                    }
                    
                    // Update project data
                    let projectData: [String: Any] = [
                        "updatedAt": timestamp,
                        "editorState": jsonDict,
                        "segments": segmentsData,
                        "videoSize": [
                            "width": result.task.video.size.width,
                            "height": result.task.video.size.height
                        ],
                        "finalVideoURL": downloadURL.absoluteString
                    ]
                    
                    // Update Firestore
                    let db = Firestore.firestore()
                    db.collection("projects").document(self.parent.project.id).updateData(projectData) { error in
                        if let error = error {
                            print("❌ [VideoEditor] Failed to update project: \(error.localizedDescription)")
                        } else {
                            print("📹 [VideoEditor] Project updated successfully")
                        }
                        self.parent.onComplete(result.output.url)
                        videoEditViewController.dismiss(animated: true)
                    }
                }
            }
        }
        
        func videoEditViewControllerDidFail(_ videoEditViewController: VideoEditViewController, error: VideoEditorError) {
            print("❌ [VideoEditor] Failed to export video: \(error.localizedDescription)")
            parent.onComplete(nil)
            videoEditViewController.dismiss(animated: true)
        }
        
        func videoEditViewControllerDidCancel(_ videoEditViewController: VideoEditViewController) {
            print("❌ [EditVideoEditor] User cancelled editing")
            parent.onComplete(nil)
            videoEditViewController.dismiss(animated: true)
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
