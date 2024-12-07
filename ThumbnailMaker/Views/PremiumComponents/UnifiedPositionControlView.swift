import SwiftUI

struct UnifiedPositionControlView: View {
    enum ControlTarget: String,CaseIterable {
        case text = "Text"
        case profile = "Profile"
    }
    
    @Binding var textPosition: (vertical: VerticalAlignment, horizontal: HorizontalAlignment)
    @Binding var profilePosition: CircularProfileConfig.ProfilePosition
    @Binding var profileSize: CGFloat
    @Binding var textSize: CGFloat
    @Binding var textColor: Color
    @State private var selectedTarget: ControlTarget = .text
    
    var body: some View {
        VStack(spacing: 12) {
            // Tab Selection Row
            HStack(spacing: 0) {
                ForEach(ControlTarget.allCases, id: \.self) { target in
                    Button(action: {
                        withAnimation {
                            selectedTarget = target
                        }
                    }) {
                        Text(target.rawValue)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(selectedTarget == target ? Color.blue : Color.clear)
                            .foregroundColor(selectedTarget == target ? .white : .primary)
                    }
                }
            }
            .background(Color(uiColor: .systemGray5))
            .cornerRadius(8)
            .padding(.horizontal)
            
            HStack(spacing: 20) {
                // Center - Position Matrix
                VStack {
                    Text("Position")
                        .font(.headline)
                    
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
                
                // Right side - Size Controls
                VStack(alignment: .leading, spacing: 8) {
                    if selectedTarget == .text {
                        Text("Text Size")
                            .font(.headline)
                        
                        Slider(value: $textSize, in: 0.1...0.3)
                            .frame(width: 120)
                            .tint(.blue)
                        
                        ColorPicker("Text Color", selection: $textColor)
                            .labelsHidden()
                            .padding(.top, 8)
                    } else {
                        Text("Profile Size")
                            .font(.headline)
                        
                        Slider(value: $profileSize, in: 0.1...0.3)
                            .frame(width: 120)
                            .tint(.blue)
                    }
                }
                .frame(width: 120)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private func isSelected(row: Int, col: Int) -> Bool {
        if selectedTarget == .text {
            let currentVertical = verticalAlignment(for: row)
            let currentHorizontal = horizontalAlignment(for: col)
            return textPosition.vertical == currentVertical && 
                   textPosition.horizontal == currentHorizontal
        } else {
            return profilePosition == position(for: row, col: col)
        }
    }
    
    private func updatePosition(row: Int, col: Int) {
        if selectedTarget == .text {
            textPosition.vertical = verticalAlignment(for: row)
            textPosition.horizontal = horizontalAlignment(for: col)
        } else {
            profilePosition = position(for: row, col: col)
        }
    }
    
    // Helper functions to convert grid positions to alignments
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
    
    private func position(for row: Int, col: Int) -> CircularProfileConfig.ProfilePosition {
        switch (row, col) {
        case (0, 0): return .topLeft
        case (0, 1): return .topCenter
        case (0, 2): return .topRight
        case (1, 0): return .middleLeft
        case (1, 1): return .middleCenter
        case (1, 2): return .middleRight
        case (2, 0): return .bottomLeft
        case (2, 1): return .bottomCenter
        case (2, 2): return .bottomRight
        default: return .topRight
        }
    }
}

struct RadioButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .stroke(Color.blue, lineWidth: 2)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Circle()
                            .fill(isSelected ? Color.blue : Color.clear)
                            .frame(width: 12, height: 12)
                    )
                Text(title)
                    .foregroundColor(.primary)
            }
        }
    }
} 
