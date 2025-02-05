import SwiftUI
import PhotosUI
import Photos
import AVFoundation

struct CreateView: View {
    @Environment(\.dismiss) var dismiss
    @State private var showRecordView = false
    @State private var showImportView = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                HStack {
                    Text("Create")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal)
                .padding(.top)
                
                // Studio Options
                VStack(spacing: 20) {
                    // Record Option
                    Button(action: {
                        showRecordView = true
                    }) {
                        StudioOptionCard(
                            icon: "video.fill",
                            title: "Record Video",
                            description: "Create a new video using your camera"
                        )
                    }
                    
                    // Import Option
                    Button(action: {
                        showImportView = true
                    }) {
                        StudioOptionCard(
                            icon: "square.and.arrow.down",
                            title: "Import Video",
                            description: "Import existing videos from your library"
                        )
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .background(Color.black.edgesIgnoringSafeArea(.all))
            .sheet(isPresented: $showRecordView) {
                // Record view will be implemented
                Color.black.edgesIgnoringSafeArea(.all)
            }
            .fullScreenCover(isPresented: $showImportView) {
                ImportVideosView()
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

struct StudioOptionCard: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.red)
                .frame(width: 56, height: 56)
                .background(Color.white.opacity(0.1))
                .clipShape(Circle())
            
            // Text Content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(2)
            }
            
            Spacer()
            
            // Arrow Icon
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
        )
    }
}

#Preview {
    CreateView()
} 