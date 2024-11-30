import SwiftUI

struct TextInputView: View {
    @Binding var text: String
    let isFocused: FocusState<Bool>.Binding
    let height: CGFloat
    let bottomID: Namespace.ID
    let proxy: ScrollViewProxy
    let topID: Namespace.ID
    
    var body: some View {
        TextEditor(text: $text)
            .frame(height: height)
            .focused(isFocused)
            .padding()
            .onChange(of: isFocused.wrappedValue) { _, isFocused in
                if isFocused {
                    proxy.scrollTo(bottomID)
                } else {
                    proxy.scrollTo(topID)
                }
            }
    }
} 
