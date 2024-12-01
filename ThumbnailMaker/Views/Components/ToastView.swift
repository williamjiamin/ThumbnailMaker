//
//  ToastView.swift
//  ThumbnailMaker
//
//  Created by william on 2024/12/1.
//

import SwiftUI

struct ToastView: View {
    let message: String
    
    var body: some View {
        Text(message)
            .padding()
            .background(Color.black.opacity(0.7))
            .foregroundColor(.white)
            .cornerRadius(10)
            .padding(.bottom, 20)
            .transition(.move(edge: .bottom))
    }
}

#Preview {
    ToastView(message: "Hello, World!")
}
