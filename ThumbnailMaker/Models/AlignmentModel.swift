//
//  AlignmentModel.swift
//  ThumbnailMaker
//
//  Created by william on 2024/11/28.
//

import Foundation

// Add enum for alignment options
enum VerticalAlignment: String, CaseIterable {
    case top = "Top"
    case center = "Center"
    case bottom = "Bottom"
}

enum HorizontalAlignment: String, CaseIterable {
    case leading = "Left"
    case center = "Center"
    case trailing = "Right"
}

//it shouldn't be here, i should use tabview for multiple main views
enum Tab: String, CaseIterable {
    case simpleMaker = "Simple Maker"
    case premium = "Premium Maker"
}
