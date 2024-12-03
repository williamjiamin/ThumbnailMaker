import SwiftUI

struct LegalDocumentView: View {
    let title: String
    let documentName: String
    
    var body: some View {
        ScrollView {
            if let filepath = Bundle.main.path(forResource: documentName, ofType: "txt"),
               let content = try? String(contentsOfFile: filepath, encoding: .utf8) {
                Text(content)
                    .padding()
            } else {
                Text("Document not found")
                    .foregroundColor(.red)
            }
        }
        .navigationTitle(title)
    }
} 