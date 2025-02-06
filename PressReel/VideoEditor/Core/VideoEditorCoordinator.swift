import SwiftUI
import VideoEditorSDK
import Photos
import AVFoundation

class VideoEditorCoordinator: NSObject, UINavigationControllerDelegate {
    private let parent: VideoEditorView
    private var completion: ((URL?) -> Void)?
    
    init(_ parent: VideoEditorView) {
        self.parent = parent
        super.init()
    }
    
    func present(with asset: PHAsset, completion: @escaping (URL?) -> Void) {
        self.completion = completion
        
        // Get VESDK configuration
        let configuration = VESDKConfiguration.defaultConfiguration()
        
        // Request video asset
        PHImageManager.default().requestAVAsset(forVideo: asset, options: nil) { [weak self] (avAsset, _, _) in
            DispatchQueue.main.async {
                guard let avAsset = avAsset else { return }
                
                // Create Video object from AVAsset
                let video = Video(asset: avAsset)
                
                // Create and present VESDK
                let videoEditViewController = VideoEditViewController(videoAsset: video, configuration: configuration)
                videoEditViewController.delegate = self
                videoEditViewController.modalPresentationStyle = .fullScreen
                
                UIApplication.shared.windows.first?.rootViewController?.present(videoEditViewController, animated: true)
            }
        }
    }
}

extension VideoEditorCoordinator: VideoEditViewControllerDelegate {
    func videoEditViewControllerDidFinish(_ videoEditViewController: VideoEditViewController, result: VideoEditorResult) {
        // Handle the edited video
        videoEditViewController.dismiss(animated: true) {
            self.completion?(result.output.url)
        }
    }
    
    func videoEditViewControllerDidFail(_ videoEditViewController: VideoEditViewController, error: VideoEditorError) {
        // Handle any errors
        videoEditViewController.dismiss(animated: true) {
            print("Video editor failed with error: \(error.localizedDescription)")
            self.completion?(nil)
        }
    }
    
    func videoEditViewControllerDidCancel(_ videoEditViewController: VideoEditViewController) {
        // Handle cancellation
        videoEditViewController.dismiss(animated: true) {
            self.completion?(nil)
        }
    }
}
