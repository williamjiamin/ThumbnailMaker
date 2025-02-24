import SwiftUI

struct YouTubeURLInputView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var youtubeURL = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var videoInfo: YouTubeVideoInfo?
    @FocusState private var isFocused: Bool
    let onSelection: (UIImage, String) -> Void
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Guide Section
                    VStack(spacing: 16) {
                        Text("How to Import from YouTube")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            guideRow(number: "1", text: "Copy a YouTube video URL")
                            guideRow(number: "2", text: "Paste the URL below")
                            guideRow(number: "3", text: "Tap 'Fetch Video Info'")
                            guideRow(number: "4", text: "Choose how to use the content")
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                    // URL Input Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Enter YouTube Video URL")
                            .font(.headline)
                        
                        TextField("https://youtube.com/watch?v=...", text: $youtubeURL)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .textContentType(.URL)
                            .focused($isFocused)
                    }
                    .padding(.horizontal)
                    
                    // Preview Section
                    if let videoInfo = videoInfo {
                        VStack(spacing: 16) {
                            Text("Preview")
                                .font(.headline)
                            
                            videoInfo.thumbnail
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 200)
                                .cornerRadius(8)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Title:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                Text(videoInfo.title)
                                    .font(.body)
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                            
                            // Action Buttons
                            VStack(spacing: 12) {
                                Button(action: {
                                    if let uiImage = videoInfo.thumbnail.asUIImage() {
                                        onSelection(uiImage, "")
                                        dismiss()
                                    }
                                }) {
                                    Label("Use Thumbnail Only", systemImage: "photo")
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .cornerRadius(10)
                                }
                                
                                Button(action: {
                                    if let uiImage = videoInfo.thumbnail.asUIImage() {
                                        // Format title for better display
                                        let formattedTitle = videoInfo.title
                                            .replacingOccurrences(of: " - YouTube", with: "")
                                            .trimmingCharacters(in: .whitespacesAndNewlines)
                                        onSelection(uiImage, formattedTitle)
                                        dismiss()
                                    }
                                }) {
                                    Label("Use Title Only", systemImage: "text.alignleft")
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .cornerRadius(10)
                                }
                                
                                Button(action: {
                                    if let uiImage = videoInfo.thumbnail.asUIImage() {
                                        onSelection(uiImage, videoInfo.title)
                                        dismiss()
                                    }
                                }) {
                                    Label("Use Both", systemImage: "text.below.photo")
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .cornerRadius(10)
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.05))
                        .cornerRadius(12)
                        .padding()
                    }
                    
                    // Fetch Button
                    if videoInfo == nil {
                        Button(action: {
                            Task {
                                await fetchVideoInfo()
                            }
                        }) {
                            HStack {
                                if isLoading {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text("Fetch Video Info")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(youtubeURL.isEmpty ? Color.gray : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .disabled(youtubeURL.isEmpty || isLoading)
                        .padding(.horizontal)
                    }
                    
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding(.horizontal)
                    }
                    
                    Spacer()
                }
                .padding(.top)
            }
            .navigationTitle("YouTube Import")
            .navigationBarTitleDisplayMode(.inline)
            .onTapGesture {
                isFocused = false
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), 
                                             to: nil, 
                                             from: nil, 
                                             for: nil)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isFocused = false
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func guideRow(number: String, text: String) -> some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.headline)
                .foregroundColor(.blue)
                .frame(width: 24, height: 24)
                .background(Circle().stroke(Color.blue, lineWidth: 2))
            
            Text(text)
                .font(.subheadline)
            
            Spacer()
        }
    }
    
    private func fetchVideoInfo() async {
        isLoading = true
        errorMessage = nil
        
        do {
            videoInfo = try await YouTubeService.fetchVideoInfo(videoURL: youtubeURL)
        } catch YouTubeError.invalidVideoID {
            errorMessage = "Invalid YouTube URL"
        } catch YouTubeError.noThumbnailFound {
            errorMessage = "Could not find thumbnail"
        } catch YouTubeError.noTitleFound {
            errorMessage = "Could not fetch video title"
        } catch {
            errorMessage = "Failed to fetch video info"
        }
        
        isLoading = false
    }
}

@MainActor
extension Image {
    func asUIImage() -> UIImage? {
        let renderer = ImageRenderer(content: self)
        return renderer.uiImage
    }
} 