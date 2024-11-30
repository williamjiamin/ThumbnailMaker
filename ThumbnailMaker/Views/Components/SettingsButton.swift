import SwiftUI


struct SettingsButton: View {
    @Binding var isPresented: Bool
    
    var body: some View {
        Button(action: {
            isPresented = true
        }) {
            Image(systemName: "gear")
        }
    }
} 
