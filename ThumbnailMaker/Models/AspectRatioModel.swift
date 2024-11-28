//
//  ThumbnailEnums.swift
//  ThumbnailMaker
//
//  Created by william on 2024/11/28.
//

import Foundation

enum AspectRatio: String, CaseIterable {
    case ratio16_9 = "16:9"
    case ratio9_16 = "9:16"
    case ratio1_1 = "1:1"
    case ratio4_3 = "4:3"
    case ratio3_4 = "3:4"
    
    var value: CGFloat {
        switch self {
        case .ratio16_9: return 16.0/9.0
        case .ratio9_16: return 9.0/16.0
        case .ratio1_1: return 1.0
        case .ratio4_3: return 4.0/3.0
        case .ratio3_4: return 3.0/4.0
        }
    }
    
    var dimensions: (width: CGFloat, height: CGFloat) {
        switch self {
        case .ratio16_9: return (1024, 576)
        case .ratio9_16: return (576, 1024)
        case .ratio1_1: return (1024, 1024)
        case .ratio4_3: return (1024, 768)
        case .ratio3_4: return (768, 1024)
        }
    }
}
