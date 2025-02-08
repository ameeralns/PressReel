import SwiftUI
import PhotosUI
import Photos
import AVFoundation

struct CreateView: View {
    @Environment(\.dismiss) var dismiss
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
                
                Spacer()
                
                // Create Project Button
                Button(action: {
                    showImportView = true
                }) {
                    VStack(spacing: 24) {
                        // Icon
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 64, weight: .semibold))
                            .foregroundColor(.red)
                            .frame(width: 120, height: 120)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                        
                        // Text Content
                        VStack(spacing: 12) {
                            Text("Create Project")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text("Import videos from your camera roll to create a new project")
                                .font(.body)
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 400)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color.white.opacity(0.05))
                    )
                    .padding(.horizontal)
                }
                
                Spacer()
            }
            .background(Color.black.edgesIgnoringSafeArea(.all))
            .fullScreenCover(isPresented: $showImportView) {
                ImportVideosView()
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}


#Preview {
    CreateView()
} 