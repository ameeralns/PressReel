import SwiftUI

@MainActor
struct LibraryView: View {
    @State private var selectedFilter = 0
    @State private var showProfile = false
    @StateObject private var authService = AuthenticationService()
    let filters = ["All", "In Progress", "Published"]
    
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
                        ForEach(0..<6) { _ in
                            ProjectCard()
                        }
                    }
                    .padding()
                }
            }
        }
        .sheet(isPresented: $showProfile) {
            ProfileView(isPresented: $showProfile)
        }
    }
}

@MainActor
struct ProjectCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.1))
                .aspectRatio(16/9, contentMode: .fit)
                .overlay(
                    Image(systemName: "play.fill")
                        .font(.callout)
                        .foregroundColor(.white)
                )
            
            Text("Project Title")
                .font(.callout)
                .fontWeight(.medium)
                .foregroundColor(.white)
            
            Text("Last edited 2h ago")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
    }
}