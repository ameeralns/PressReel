import SwiftUI

struct ScriptView: View {
    @State private var showCopiedFeedback = false
    let script: Script
    @Environment(\.dismiss) private var dismiss
    
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
                }
                .padding()
                .background(Color.black.opacity(0.8))
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Script Title
                        Text(script.title)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        // Article Info
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Based on article:")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                            
                            Text(script.articleTitle)
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            Link(destination: URL(string: script.articleUrl)!) {
                                Text("View Original Article")
                                    .font(.subheadline)
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.vertical, 8)
                        
                        // Script Content
                        Text(script.content)
                            .font(.body)
                            .foregroundColor(.white)
                            .lineSpacing(8)
                    }
                    .padding()
                    
                    // Copy Button
                    Button(action: {
                        UIPasteboard.general.string = script.content
                        showCopiedFeedback = true
                        
                        // Hide feedback after 2 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            showCopiedFeedback = false
                        }
                    }) {
                        HStack {
                            Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                            Text(showCopiedFeedback ? "Copied!" : "Copy Script")
                        }
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(showCopiedFeedback ? Color.green : Color.red)
                        )
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                }
            }
        }
        .navigationBarHidden(true)
    }
}
