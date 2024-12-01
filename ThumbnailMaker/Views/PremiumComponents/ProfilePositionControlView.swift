import SwiftUI

struct ProfilePositionControlView: View {
    @Binding var position: CircularProfileConfig.ProfilePosition
    
    var body: some View {
        VStack(spacing: 8) {
            Text("Profile Position")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(0..<3) { row in
                    GridRow {
                        ForEach(0..<3) { col in
                            let pos = position(for: row, col: col)
                            Circle()
                                .stroke(position == pos ? Color.blue : Color.gray)
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Circle()
                                        .fill(position == pos ? Color.blue : Color.clear)
                                        .frame(width: 15, height: 15)
                                )
                                .onTapGesture {
                                    position = pos
                                }
                        }
                    }
                }
            }
        }
        .padding()
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
        default: return .topLeft
        }
    }
} 
