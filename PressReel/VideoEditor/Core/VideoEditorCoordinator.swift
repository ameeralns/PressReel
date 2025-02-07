import SwiftUI
import VideoEditorSDK
import Photos
import AVFoundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "VideoEditor")

class VideoEditorCoordinator: NSObject, UINavigationControllerDelegate {
    private let parent: VideoEditorView
    private var completion: ((URL?) -> Void)?
    
    init(_ parent: VideoEditorView) {
        NSLog("📹 [VideoEditor] Initializing VideoEditorCoordinator")
        logger.debug("Initializing VideoEditorCoordinator")
        self.parent = parent
        super.init()
        NSLog("📹 [VideoEditor] VideoEditorCoordinator initialized successfully")
        logger.debug("VideoEditorCoordinator initialized successfully")
        
        // Force flush the log buffer
        fflush(stdout)
    }
    
    func present(with asset: PHAsset, completion: @escaping (URL?) -> Void) {
        NSLog("📹 [VideoEditor] Starting presentation with PHAsset: %@", asset.localIdentifier)
        print("📹 [VideoEditor] Starting presentation with PHAsset")
        self.completion = completion
        
        // Get VESDK configuration
        print("📹 [VideoEditor] Getting VESDK configuration")
        let configuration = VESDKConfiguration.defaultConfiguration()
        
        // Request video asset
        print("📹 [VideoEditor] Requesting video asset from PHImageManager")
        PHImageManager.default().requestAVAsset(forVideo: asset, options: nil) { [weak self] (avAsset, _, _) in
            DispatchQueue.main.async {
                guard let avAsset = avAsset else {
                    print("❌ [VideoEditor] Failed to get AVAsset from PHAsset")
                    return
                }
                print("📹 [VideoEditor] Successfully received AVAsset")
                
                // Create Video object from AVAsset
                print("📹 [VideoEditor] Creating Video object from AVAsset")
                let video = Video(asset: avAsset)
                
                // Create and present VESDK
                print("📹 [VideoEditor] Creating VideoEditViewController")
                let videoEditViewController = VideoEditViewController(videoAsset: video, configuration: configuration)
                videoEditViewController.delegate = self
                videoEditViewController.modalPresentationStyle = .fullScreen
                
                print("📹 [VideoEditor] Preparing to present VideoEditViewController")
                
                // Get the active scene and its root view controller
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first,
                   let rootViewController = window.rootViewController?.presentedViewController ?? window.rootViewController {
                    print("📹 [VideoEditor] Found root view controller, presenting editor")
                    rootViewController.present(videoEditViewController, animated: true) {
                        print("📹 [VideoEditor] VideoEditViewController presented successfully")
                    }
                } else {
                    print("❌ [VideoEditor] Failed to find appropriate view controller for presentation")
                }
            }
        }
    }
}

extension VideoEditorCoordinator: VideoEditViewControllerDelegate {
    func videoEditViewControllerDidFinish(_ videoEditViewController: VideoEditViewController, result: VideoEditorResult) {
        print("📹 [VideoEditor] Editing completed successfully")
        print("📹 [VideoEditor] Output URL: \(result.output.url)")
        
        // Handle the edited video and transition to library view
        print("📹 [VideoEditor] Dismissing VideoEditViewController")
        videoEditViewController.dismiss(animated: true) {
            print("📹 [VideoEditor] VideoEditViewController dismissed")
            self.completion?(result.output.url)
            
            // Present the library view
            print("📹 [VideoEditor] Preparing to present LibraryView")
            DispatchQueue.main.async {
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first,
                   let rootVC = window.rootViewController {
                    print("📹 [VideoEditor] Creating LibraryView")
                    let libraryView = LibraryView()
                    let hostingController = UIHostingController(rootView: libraryView)
                    hostingController.modalPresentationStyle = .fullScreen
                    
                    print("📹 [VideoEditor] Presenting LibraryView")
                    rootVC.present(hostingController, animated: true) {
                        print("📹 [VideoEditor] LibraryView presented successfully")
                    }
                } else {
                    print("❌ [VideoEditor] Failed to get window scene or root view controller")
                }
            }
        }
    }
    
    func videoEditViewControllerDidFail(_ videoEditViewController: VideoEditViewController, error: VideoEditorError) {
        print("❌ [VideoEditor] Editor failed with error: \(error.localizedDescription)")
        print("❌ [VideoEditor] Error details: \(error)")
        
        // Handle any errors
        print("📹 [VideoEditor] Dismissing VideoEditViewController after error")
        videoEditViewController.dismiss(animated: true) {
            print("📹 [VideoEditor] VideoEditViewController dismissed after error")
            self.completion?(nil)
        }
    }
    
    func videoEditViewControllerDidCancel(_ videoEditViewController: VideoEditViewController) {
        print("📹 [VideoEditor] User cancelled editing")
        
        // Handle cancellation
        print("📹 [VideoEditor] Dismissing VideoEditViewController after cancellation")
        videoEditViewController.dismiss(animated: true) {
            print("📹 [VideoEditor] VideoEditViewController dismissed after cancellation")
            self.completion?(nil)
        }
    }
}
