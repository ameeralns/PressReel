import SwiftUI
import VideoEditorSDK
import Photos
import UIKit

struct VideoEditorView: View {
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
                    DispatchQueue.main.async {
                        onComplete(nil)
                        presentationMode.wrappedValue.dismiss()
                    }
                    return
                }
                
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
                            // Save to camera roll
                            PHPhotoLibrary.shared().performChanges {
                                let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: result.output.url)
                                request?.creationDate = Date()
                            } completionHandler: { success, error in
                                DispatchQueue.main.async {
                                    if success {
                                        print("📹 [VideoEditor] Saved to camera roll")
                                    } else if let error = error {
                                        print("❌ [VideoEditor] Failed to save to camera roll: \(error.localizedDescription)")
                                    }
                                    onComplete(result.output.url)
                                    dismissAll()
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

