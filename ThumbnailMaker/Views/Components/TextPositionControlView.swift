import SwiftUI

struct TextPositionControlView: View {
    @Binding var verticalAlignment: VerticalAlignment
    @Binding var horizontalAlignment: HorizontalAlignment
    @Binding var textSize: CGFloat
    @Binding var textColor: Color
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Text Controls")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 20) {
                // Position Matrix
                VStack {
                    Text("Position")
                        .font(.subheadline)
                    
                    Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                        ForEach(0..<3) { row in
                            GridRow {
                                ForEach(0..<3) { col in
                                    Button(action: {
                                        updatePosition(row: row, col: col)
                                    }) {
                                        Circle()
                                            .stroke(isSelected(row: row, col: col) ? Color.blue : Color.gray)
                                            .frame(width: 30, height: 30)
                                            .overlay(
                                                Circle()
                                                    .fill(isSelected(row: row, col: col) ? Color.blue : Color.clear)
                                                    .frame(width: 15, height: 15)
                                            )
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Size and Color Controls
                VStack(alignment: .leading, spacing: 8) {
                    Text("Text Size")
                        .font(.subheadline)
                    
                    Slider(value: $textSize, in: 0.1...0.3)
                        .frame(width: 120)
                        .tint(.blue)
                    
                    ColorPicker("Text Color", selection: $textColor)
                        .labelsHidden()
                        .padding(.top, 8)
                }
                .frame(width: 120)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private func isSelected(row: Int, col: Int) -> Bool {
        let currentVertical = verticalAlignment(for: row)
        let currentHorizontal = horizontalAlignment(for: col)
        return verticalAlignment == currentVertical && 
               horizontalAlignment == currentHorizontal
    }
    
    private func updatePosition(row: Int, col: Int) {
        verticalAlignment = verticalAlignment(for: row)
        horizontalAlignment = horizontalAlignment(for: col)
    }
    
    private func verticalAlignment(for row: Int) -> VerticalAlignment {
        switch row {
        case 0: return .top
        case 1: return .center
        case 2: return .bottom
        default: return .center
        }
    }
    
    private func horizontalAlignment(for col: Int) -> HorizontalAlignment {
        switch col {
        case 0: return .leading
        case 1: return .center
        case 2: return .trailing
        default: return .center
        }
    }
} 