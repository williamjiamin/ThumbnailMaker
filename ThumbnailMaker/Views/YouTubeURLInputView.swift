import SwiftUI
import Network

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
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
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
            ScrollView {
                VStack(spacing: 24) {
                    // Quota Information Section
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                            Text("Import Quota")
                                .font(.headline)
                                .foregroundColor(.primary)
                        }
                        
                        HStack(spacing: 16) {
                            VStack(alignment: .center, spacing: 4) {
                                Text("\(purchaseManager.youtubeImportsRemaining)")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.blue)
                                Text("Remaining")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            
                            Divider().frame(height: 30)
                            
                            VStack(alignment: .center, spacing: 4) {
                                Text(purchaseManager.purchasedProductIDs.isEmpty ? "3" : "100")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.secondary)
                                Text("Daily Limit")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            
                            if purchaseManager.youtubeImportsRemaining < (purchaseManager.purchasedProductIDs.isEmpty ? 3 : 100) {
                                Divider().frame(height: 30)
                                
                                VStack(alignment: .center, spacing: 4) {
                                    Text(purchaseManager.timeUntilNextReset)
                                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                                        .foregroundColor(.orange)
                                    Text("Until Reset")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // Guide Section - Always show this
                    if !isQuotaReached {
                        VStack(spacing: 16) {
                            Text("How to Import from YouTube")
                                .font(.headline)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                guideRow(number: "1", text: "Open your YouTube video")
                                guideRow(number: "2", text: "Tap the Share button")
                                guideRow(number: "3", text: "Select 'Copy Link'")
                                guideRow(number: "4", text: "Paste the link below")
                                guideRow(number: "5", text: "Tap 'Fetch Video Info'")
                                Text("Premium users: 100 imports per day | Free users: 3 imports per day")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 36)
                            }
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)
                        
                        // Disclaimer Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Important Notice")
                                .font(.headline)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("By using this feature, you acknowledge:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    disclaimerRow("Internet connection required")
                                    disclaimerRow("Limited to 3 imports per day (free) or 100 imports per day (premium)")
                                    disclaimerRow("Only supports regular YouTube videos (not Shorts)")
                                    disclaimerRow("YouTube thumbnails may be protected by copyright")
                                    disclaimerRow("Only use your own content or properly licensed thumbnails")
                                    disclaimerRow("This feature is for reference and inspiration only")
                                    disclaimerRow("Using imported thumbnails commercially may violate copyright laws")
                                    disclaimerRow("We are not responsible for any copyright violations")
                                    disclaimerRow("Subject to YouTube API Terms of Service")
                                }
                            }
                            .padding()
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }
                    
                    // URL Input Section
                    if !isQuotaReached {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Enter YouTube Video URL")
                                .font(.headline)
                            
                            TextField("https://youtube.com/watch?v=...", text: $youtubeURL)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .textContentType(.URL)
                                .keyboardType(.URL)
                                .focused($isFocused)
                                .textSelection(.enabled)
                                .contextMenu {
                                    Button {
                                        UIPasteboard.general.string.map { youtubeURL = $0 }
                                    } label: {
                                        Label("Paste", systemImage: "doc.on.clipboard")
                                    }
                                    
                                    Button {
                                        youtubeURL = ""
                                    } label: {
                                        Label("Clear", systemImage: "xmark")
                                    }
                                }
                        }
                        .padding(.horizontal)
                    } else {
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(.red)
                                Text(purchaseManager.purchasedProductIDs.isEmpty ? 
                                    "Daily Free Import Limit Reached" : 
                                    "Daily Premium Import Limit Reached")
                                    .font(.headline)
                                    .foregroundColor(.red)
                            }
                            
                            Text("Your imports will reset tomorrow at midnight.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Image(systemName: "clock")
                                    .foregroundColor(.secondary)
                                Text("Next reset in: \(purchaseManager.timeUntilNextReset)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 4)
                        }
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                    
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
                    if videoInfo == nil && !isQuotaReached {
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
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .disabled(isButtonDisabled)
                        .opacity(isButtonDisabled ? 0.5 : 1)
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
            .simultaneousGesture(
                TapGesture()
                    .onEnded { _ in
                        // Only dismiss keyboard if it's currently showing
                        if isFocused {
                            isFocused = false
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                          to: nil,
                                                          from: nil,
                                                          for: nil)
                        }
                    }
            )
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isFocused = false
                        dismiss()
                    }
                }
            }
        }
        
        #if DEBUG
        .overlay(alignment: .top) {
            if DebugSettings.isDebugMode {
                Text("DEBUG MODE: \(DebugSettings.premiumQuotaLimit) premium imports, resets every 3 minutes")
                    .font(.caption2)
                    .padding(4)
                    .background(Color.red.opacity(0.2))
                    .cornerRadius(4)
                    .padding(.top, 4)
            }
        }
        #endif
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
    
    private func disclaimerRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundColor(.orange)
            
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func fetchVideoInfo() async {
        guard networkMonitor.isConnected else {
            errorMessage = "No internet connection. Please check your network settings."
            return
        }
        
        isLoading = true
        
        let importStatus = purchaseManager.useYoutubeImport()
        
        await MainActor.run {
            switch importStatus {
            case .limitReachedPremium:
                errorMessage = "You've reached today's import limit. Your imports will reset tomorrow at midnight."
                isLoading = false
                return
                
            case .limitReachedFree:
                errorMessage = "You've reached the daily free import limit. Upgrade to Premium for more imports."
                isLoading = false
                return
                
            case .success:
                break // Continue with the fetch
            }
        }
        
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


