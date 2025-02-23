import SwiftUI

struct YouTubeURLInputView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var youtubeURL = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    let onImageSelected: (UIImage) -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // YouTube URL Input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Enter YouTube Video URL")
                        .font(.headline)
                    
                    TextField("https://youtube.com/watch?v=...", text: $youtubeURL)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .textContentType(.URL)
                }
                .padding(.horizontal)
                
                // Use Button
                Button(action: {
                    Task {
                        await fetchThumbnail()
                    }
                }) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        }
                        Text("Use Thumbnail")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(youtubeURL.isEmpty ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(youtubeURL.isEmpty || isLoading)
                .padding(.horizontal)
                
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                }
                
                Spacer()
            }
            .padding(.top)
            .navigationTitle("YouTube Thumbnail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func fetchThumbnail() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let image = try await YouTubeService.fetchThumbnail(videoURL: youtubeURL)
            if let uiImage = image.asUIImage() {
                onImageSelected(uiImage)
                dismiss()
            } else {
                errorMessage = "Failed to process thumbnail"
            }
        } catch YouTubeError.invalidVideoID {
            errorMessage = "Invalid YouTube URL"
        } catch YouTubeError.noThumbnailFound {
            errorMessage = "Could not find thumbnail"
        } catch {
            errorMessage = "Failed to fetch thumbnail"
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