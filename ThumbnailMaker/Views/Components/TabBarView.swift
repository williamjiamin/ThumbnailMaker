import SwiftUI

struct TabBarView: View {
    @Binding var selectedTab: Tab
    
    var body: some View {
        HStack {
            Button(action: {
                withAnimation {
                    selectedTab = .simpleMaker
                }
            }) {
                VStack {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 24))
                    Text("Simple Maker")
                        .font(.caption)
                }
            }
            .foregroundColor(selectedTab == .simpleMaker ? .blue : .gray)
            
            Spacer()
            
            Button(action: {
                withAnimation {
                    selectedTab = .premium
                }
            }) {
                VStack {
                    Image(systemName: "star.circle")
                        .font(.system(size: 24))
                    Text("Premium")
                        .font(.caption)
                }
            }
            .foregroundColor(selectedTab == .premium ? .blue : .gray)
        }
        .padding(.horizontal, 50)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground))
    }
} 
