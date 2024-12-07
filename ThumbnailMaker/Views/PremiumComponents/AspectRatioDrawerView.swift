import SwiftUI

struct AspectRatioDrawerView: View {
    @Binding var selectedRatio: AspectRatio
    @Binding var isPresented: Bool
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Handle bar
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 40, height: 4)
                .cornerRadius(2)
                .padding(.top, 8)
                .padding(.bottom, 16)
            
            Text("Select Aspect Ratio")
                .font(.headline)
                .padding(.bottom, 16)
            
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(AspectRatio.allCases, id: \.self) { ratio in
                        Button(action: {
                            selectedRatio = ratio
                            withAnimation {
                                isPresented = false
                            }
                        }) {
                            HStack {
                                Text(ratio.rawValue)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                if selectedRatio == ratio {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(selectedRatio == ratio ? Color.blue.opacity(0.1) : Color.clear)
                            .contentShape(Rectangle())
                        }
                    }
                }
            }
            .padding(.bottom, 30)
        }
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(16)
        .gesture(
            DragGesture()
                .onEnded { gesture in
                    if gesture.translation.height > 50 {
                        withAnimation {
                            isPresented = false
                        }
                    }
                }
        )
    }
} 