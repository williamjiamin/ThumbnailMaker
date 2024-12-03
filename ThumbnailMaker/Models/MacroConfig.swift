import SwiftUI

struct MacroConfig {
    var isEnabled: Bool = false
    var startNumber: Int = 1
    var endNumber: Int = 1
    var appendPosition: AppendPosition = .after
    
    enum AppendPosition: String, CaseIterable {
        case before = "Before"
        case after = "After"
    }
    
    var isValid: Bool {
        let difference = abs(endNumber - startNumber)
        return difference < 100 && difference >= 0
    }
    
    var totalCount: Int {
        abs(endNumber - startNumber) + 1
    }
} 