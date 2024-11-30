import SwiftUI

struct SaveAlert {
    let error: String?
    
    var alert: Alert {
        Alert(
            title: Text(error == nil ? "Success" : "Error"),
            message: Text(error ?? "Image saved successfully"),
            dismissButton: .default(Text("OK"))
        )
    }
} 
