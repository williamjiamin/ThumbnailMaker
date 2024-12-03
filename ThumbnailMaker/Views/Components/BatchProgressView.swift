import SwiftUI

struct BatchProgressView: View {
    let progress: Double
    let currentNumber: Int
    let totalCount: Int
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(.blue)
            
            Text("Generating \(currentNumber) of \(totalCount)")
                .font(.subheadline)
            
            Button(action: onCancel) {
                Text("Cancel")
                    .foregroundColor(.red)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.red, lineWidth: 1)
                    )
            }
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(12)
        .shadow(radius: 5)
    }
} 
