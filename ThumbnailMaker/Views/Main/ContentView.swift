//  ContentView.swift
//  ThumbnailMaker
//
//  Created by william on 2024/11/22.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Tab = .simpleMaker
    
    var body: some View {
        TabView(selection: $selectedTab) {
            SimpleMakerView()
                .tabItem {
                    Label("Simple", systemImage: "square.grid.2x2")
                }
                .tag(Tab.simpleMaker)
            
            PremiumMakerView()
                .tabItem {
                    Label("Premium", systemImage: "star.circle")
                }
                .tag(Tab.premium)
        }
    }
}

#Preview {
    ContentView()
}
