//
//  PremiumMakerConfigurationModel.swift
//  ThumbnailMaker
//
//  Created by william on 2024/11/28.
//

import Foundation
import SwiftUI

struct PremiumMakerConfigurationModel {
    var selectedImage: UIImage?
    var overlayText: String = ""
    var selectedRatio: AspectRatio = .ratio16_9
    var backgroundColor: Color = Color(uiColor: .secondarySystemBackground)
    var textColor: Color = .white
    var textSize: CGFloat = 0.15
    var verticalAlignment: VerticalAlignment = .center
    var horizontalAlignment: HorizontalAlignment = .center
    var circularProfile: CircularProfileConfig?
    var macroConfig: MacroConfig = MacroConfig()
}
