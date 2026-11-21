//
//  ThumbnailMakerApp.swift
//  ThumbnailMaker
//
//  Created by william on 2024/11/22.
//

import SwiftUI

@main
struct ThumbnailMakerApp: App {
    init() {
        FontManager.shared.registerFonts()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
