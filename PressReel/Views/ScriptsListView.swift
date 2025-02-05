import SwiftUI
import FirebaseFirestore

class ScriptsListViewModel: ObservableObject {
    @Published var scripts: [Script] = []
    @Published var isLoading = false
    @Published var error: Error?
    
    private let scriptService = ScriptService()
    private let userId: String
    
    init(userId: String) {
        self.userId = userId
    }
    
    @MainActor
    func loadScripts() async {
        isLoading = true
        error = nil
        
        do {
            scripts = try await scriptService.getScripts(for: userId)
        } catch {
            self.error = error
        }
        
        isLoading = false
    }
}

struct ScriptsListView: View {
    @StateObject private var viewModel: ScriptsListViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedScript: Script?
    
    init(userId: String) {
        _viewModel = StateObject(wrappedValue: ScriptsListViewModel(userId: userId))
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Custom Navigation Bar
                HStack {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    Text("Scripts")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Spacer()
                }
                .padding()
                .background(Color.black.opacity(0.8))
                
                if viewModel.isLoading {
                    Spacer()
                    ProgressView()
                        .tint(.white)
                    Spacer()
                } else if viewModel.scripts.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.6))
                        Text("No Scripts Yet")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("Generate scripts from articles in your feed")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(viewModel.scripts) { script in
                                Button(action: { selectedScript = script }) {
                                    ScriptListItem(script: script)
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .task {
            await viewModel.loadScripts()
        }
        .sheet(item: $selectedScript) { script in
            NavigationView {
                ScriptView(script: script)
            }
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.error?.localizedDescription ?? "An error occurred")
        }
    }
}

struct ScriptListItem: View {
    let script: Script
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(script.title)
                .font(.headline)
                .foregroundColor(.white)
            
            Text(script.articleTitle)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(2)
            
            Text(formatDate(script.createdAt))
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
