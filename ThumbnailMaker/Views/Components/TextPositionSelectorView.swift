import SwiftUI

struct TextPositionSelectorView: View {
    @Binding var verticalAlignment: VerticalAlignment
    @Binding var horizontalAlignment: HorizontalAlignment
    
    var body: some View {
        VStack(spacing: 8) {
            Text("Text Position")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            
            VStack(spacing: 8) {
                // Vertical alignment
                HStack {
                    Text("Vertical:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Picker("", selection: $verticalAlignment) {
                        ForEach(VerticalAlignment.allCases, id: \.self) { alignment in
                            Text(alignment.rawValue).tag(alignment)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                // Horizontal alignment
                HStack {
                    Text("Horizontal:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Picker("", selection: $horizontalAlignment) {
                        ForEach(HorizontalAlignment.allCases, id: \.self) { alignment in
                            Text(alignment.rawValue).tag(alignment)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .padding(.horizontal)
        }
    }
} 
