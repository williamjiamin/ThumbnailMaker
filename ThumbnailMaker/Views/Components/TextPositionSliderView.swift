import SwiftUI

struct TextPositionSliderView: View {
    @Binding var verticalPosition: CGFloat
    @Binding var horizontalPosition: CGFloat
    
    var body: some View {
        VStack(spacing: 8) {
            Text("Text Position")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            
            VStack(spacing: 12) {
                // Vertical position slider
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Vertical:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(verticalPositionText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(value: $verticalPosition, in: 0...1) {
                        Text("Vertical Position")
                    }
                    .tint(.blue)
                }
                
                // Horizontal position slider
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Horizontal:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(horizontalPositionText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(value: $horizontalPosition, in: 0...1) {
                        Text("Horizontal Position")
                    }
                    .tint(.blue)
                }
            }
            .padding(.horizontal)
        }
    }
    
    private var verticalPositionText: String {
        switch verticalPosition {
        case ..<0.33: return "Top"
        case 0.33..<0.66: return "Center"
        default: return "Bottom"
        }
    }
    
    private var horizontalPositionText: String {
        switch horizontalPosition {
        case ..<0.33: return "Left"
        case 0.33..<0.66: return "Center"
        default: return "Right"
        }
    }
}

#Preview {
    TextPositionSliderView(
        verticalPosition: .constant(0.5),
        horizontalPosition: .constant(0.5)
    )
} 