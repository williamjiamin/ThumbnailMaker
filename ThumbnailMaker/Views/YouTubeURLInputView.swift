import SwiftUI
import Network
import Combine

struct YouTubeURLInputView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var youtubeURL = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var videoInfo: YouTubeVideoInfo?
    @FocusState private var isFocused: Bool
    let onSelection: (UIImage, String) -> Void
    @StateObject private var networkMonitor = NetworkMonitor()
    @StateObject private var purchaseManager = PurchaseManager.shared
    @State private var currentTime = Date()
    
    // Use a cancellable timer instead of a fixed one
    @State private var timerCancellable: AnyCancellable?
    
    // Don't check pasteboard automatically
    @State private var pasteboardHasContent = false
    
    private var isButtonDisabled: Bool {
        youtubeURL.isEmpty || 
        isLoading || 
        purchaseManager.youtubeImportsRemaining <= 0 ||
        videoInfo != nil
    }
    
    private var isQuotaReached: Bool {
        purchaseManager.youtubeImportsRemaining <= 0
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if !networkMonitor.isConnected {
                    // No internet connection warning
                    NoInternetView()
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Header and information
                            VStack(spacing: 8) {
                                Text("Import YouTube Thumbnail")
                                    .font(.headline)
                                    .padding(.top)
                                
                                Text("Use the buttons below to paste a YouTube video link")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                            
                            // Quota information
                            QuotaInfoView(
                                remainingImports: purchaseManager.availableYoutubeImports,
                                isPremium: !purchaseManager.purchasedProductIDs.isEmpty
                            )
                            
                            // URL Display and Paste Controls
                            VStack(spacing: 16) {
                                // Read-only URL display field
                                HStack {
                                    Text(youtubeURL.isEmpty ? "No URL pasted yet" : youtubeURL)
                                        .foregroundColor(youtubeURL.isEmpty ? .secondary : .primary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .padding()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                                .background(Color(.systemGray6).cornerRadius(8))
                                        )
                                }
                                .padding(.horizontal)
                                
                                // Action buttons
                                HStack(spacing: 12) {
                                    // Paste button
                                    Button(action: {
                                        if let pasteboardString = UIPasteboard.general.string {
                                            youtubeURL = pasteboardString
                                        }
                                    }) {
                                        HStack {
                                            Image(systemName: "doc.on.clipboard")
                                            Text("Paste from Clipboard")
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.blue)
                                    .disabled(isLoading || videoInfo != nil)
                                    
                                    // Clear button
                                    Button(action: {
                                        youtubeURL = ""
                                        errorMessage = nil
                                    }) {
                                        HStack {
                                            Image(systemName: "xmark")
                                            Text("Clear")
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.red)
                                    .disabled(youtubeURL.isEmpty || isLoading || videoInfo != nil)
                                }
                                .padding(.horizontal)
                            }
                            
                            // Error message
                            if let errorMessage = errorMessage {
                                Text(errorMessage)
                                    .font(.footnote)
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.horizontal)
                            }
                            
                            // Get Thumbnail Button
                            Button(action: {
                                fetchVideoInfo()
                            }) {
                                if isLoading {
                                    ProgressView()
                                        .padding()
                                } else {
                                    Text("Get Thumbnail")
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .padding(.horizontal)
                            .disabled(isButtonDisabled)
                            
                            // YouTube Premium upsell for non-premium users with quota reached
                            if isQuotaReached && purchaseManager.purchasedProductIDs.isEmpty {
                                premiumUpgradeButton
                            }
                            
                            // Video thumbnail result
                            if let videoInfo = videoInfo {
                                thumbnailResultView(videoInfo: videoInfo, thumbnail: videoInfo.thumbnail)
                            }
                            
                            Spacer(minLength: 20)
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("YouTube Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            // Start the timer when the view appears
            startTimer()
        }
        .onDisappear {
            // Cancel the timer when the view disappears
            timerCancellable?.cancel()
        }
    }
    
    private func startTimer() {
        // Create a new timer that runs every minute
        timerCancellable = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                // Only update time without causing unnecessary UI refreshes
                currentTime = Date()
            }
    }
    
    private var premiumUpgradeButton: some View {
        Button(action: {
            // Show premium upgrade
        }) {
            VStack(spacing: 8) {
                Text("Get Premium for Unlimited Imports")
                    .font(.headline)
                
                Text("Unlock unlimited YouTube thumbnail imports and more premium features")
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue.opacity(0.1))
            .foregroundColor(.blue)
            .cornerRadius(8)
        }
        .padding(.horizontal)
    }
    
    private func thumbnailResultView(videoInfo: YouTubeVideoInfo, thumbnail: Image) -> some View {
        VStack(spacing: 12) {
            Text("Thumbnail Found!")
                .font(.headline)
                .foregroundColor(.green)
            
            thumbnail
                .resizable()
                .aspectRatio(contentMode: .fit)
                .cornerRadius(8)
                .shadow(radius: 3)
                .padding(.horizontal)
            
            Text(videoInfo.title)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button(action: {
                // Get the UIImage from the Image view
                if let uiImage = imageFromThumbnail(thumbnail) {
                    onSelection(uiImage, videoInfo.title)
                    dismiss()
                }
            }) {
                Text("Use This Thumbnail")
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    // Helper function to convert SwiftUI Image to UIImage
    private func imageFromThumbnail(_ image: Image) -> UIImage? {
        // This is a workaround since we need the UIImage for the callback
        // In a real app, you'd probably store the UIImage directly
        let renderer = ImageRenderer(content: image.resizable().aspectRatio(contentMode: .fit))
        return renderer.uiImage
    }
    
    private func fetchVideoInfo() {
        guard !youtubeURL.isEmpty else { return }
        
        // Check quota first
        if purchaseManager.youtubeImportsRemaining <= 0 {
            errorMessage = "Daily limit reached"
            return
        }
        
        // Use YouTube import quota
        let status = purchaseManager.useYoutubeImport()
        guard status == .success else {
            // Show quota limit screen
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        // Fetch video info
        Task {
            do {
                let result = try await YouTubeService.fetchVideoInfo(videoURL: youtubeURL)
                await MainActor.run {
                    videoInfo = result
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Error fetching thumbnail: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
}

struct QuotaInfoView: View {
    let remainingImports: Int
    let isPremium: Bool
    
    var body: some View {
        HStack {
            Image(systemName: "info.circle")
                .foregroundColor(.blue)
            
            if isPremium {
                Text("Premium: \(remainingImports) imports remaining today")
                    .font(.caption)
                    .foregroundColor(.blue)
            } else {
                Text("Free: \(remainingImports) imports remaining today")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(16)
    }
}

struct NoInternetView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 50))
                .foregroundColor(.red)
            
            Text("No Internet Connection")
                .font(.headline)
            
            Text("This feature requires an internet connection to download thumbnails from YouTube.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    YouTubeURLInputView { _, _ in }
}


