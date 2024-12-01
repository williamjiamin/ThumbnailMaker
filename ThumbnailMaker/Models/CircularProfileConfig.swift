import SwiftUI

struct CircularProfileConfig {
    var image: UIImage?
    var position: ProfilePosition
    var size: CGFloat = 0.2 // Relative to parent view size
    
    enum ProfilePosition {
        case topLeft, topCenter, topRight
        case middleLeft, middleCenter, middleRight
        case bottomLeft, bottomCenter, bottomRight
        
        var alignment: Alignment {
            switch self {
            case .topLeft: return Alignment(horizontal: .leading, vertical: .top)
            case .topCenter: return Alignment(horizontal: .center, vertical: .top)
            case .topRight: return Alignment(horizontal: .trailing, vertical: .top)
            case .middleLeft: return Alignment(horizontal: .leading, vertical: .center)
            case .middleCenter: return Alignment(horizontal: .center, vertical: .center)
            case .middleRight: return Alignment(horizontal: .trailing, vertical: .center)
            case .bottomLeft: return Alignment(horizontal: .leading, vertical: .bottom)
            case .bottomCenter: return Alignment(horizontal: .center, vertical: .bottom)
            case .bottomRight: return Alignment(horizontal: .trailing, vertical: .bottom)
            }
        }
    }
} 
