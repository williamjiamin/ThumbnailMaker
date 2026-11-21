import Foundation

struct DebugSettings {
    // MARK: - Debug Mode Configuration
    // ⚠️ Change this value to toggle between debug and production modes
    // Set to true for testing, false for App Store submission
    #if DEBUG
    static let isDebugMode = true
    #else
    static let isDebugMode = false
    #endif
    
    // Debug quota settings
    static let debugPremiumQuotaLimit = 5  // 5 imports in debug mode
    static let debugFreeQuotaLimit = 3     // 3 imports in debug mode (same as production)
    static let debugResetInterval: TimeInterval = 180  // 3 minutes
    
    // Production quota settings
    static let productionPremiumQuotaLimit = 500  // 500 imports in production
    static let productionFreeQuotaLimit = 3       // 3 imports in production
    static let productionResetInterval: TimeInterval = 86400  // 24 hours
    
    // MARK: - Accessor Methods
    static var premiumQuotaLimit: Int {
        return isDebugMode ? debugPremiumQuotaLimit : productionPremiumQuotaLimit
    }
    
    static var freeQuotaLimit: Int {
        return isDebugMode ? debugFreeQuotaLimit : productionFreeQuotaLimit
    }
    
    static var quotaResetInterval: TimeInterval {
        return isDebugMode ? debugResetInterval : productionResetInterval
    }
    
    static var modeDescription: String {
        return isDebugMode ? "Debug Mode" : "Production Mode"
    }
}

extension UserDefaults {
    func contains(key: String) -> Bool {
        return object(forKey: key) != nil
    }
} 