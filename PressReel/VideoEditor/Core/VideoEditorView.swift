import SwiftUI
import PhotosUI

struct VideoEditorView: UIViewControllerRepresentable {
    let asset: PHAsset
    let onComplete: (URL?) -> Void
    
    func makeCoordinator() -> VideoEditorCoordinator {
        VideoEditorCoordinator(self)
    }
    
    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        context.coordinator.present(with: asset, completion: onComplete)
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // No updates needed
    }
}
