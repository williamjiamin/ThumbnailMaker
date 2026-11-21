import SwiftUI
import Combine

struct QuotaLimitView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var purchaseManager = PurchaseManager.shared
    @State private var timerRefreshTrigger = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.red)
                        Text(!purchaseManager.isPremium ? 
                            "Daily Free Import Limit Reached" : 
                            "Daily Premium Import Limit Reached")
                            .font(.headline)
                            .foregroundColor(.red)
                    }
                    
                    Text("Your imports will reset tomorrow at midnight.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    // Enhanced timer display
                    VStack(spacing: 8) {
                        Text("Next reset in:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(purchaseManager.timeUntilNextReset)
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .foregroundColor(.red)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 12)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .padding(.top, 8)
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)
            }
            .navigationTitle("YouTube Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .onReceive(timer) { _ in
                timerRefreshTrigger = Date()
            }
        }
    }
}

#Preview {
    QuotaLimitView()
} 