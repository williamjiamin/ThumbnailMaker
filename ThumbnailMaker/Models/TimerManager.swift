import Foundation
import Combine

@MainActor
class TimerManager: ObservableObject {
    static let shared = TimerManager()
    
    @Published private(set) var currentTime = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var cancellables = Set<AnyCancellable>()
    
    // Add publisher for other classes to subscribe to
    var datePublisher: AnyPublisher<Date, Never> {
        $currentTime.eraseToAnyPublisher()
    }
    
    #if DEBUG
    private var debugTimer: AnyCancellable?
    #endif
    
    private init() {
        timer.sink { [weak self] date in
            self?.currentTime = date
            Task { @MainActor in
                self?.updateDebugInfo()
            }
        }
        .store(in: &cancellables)
    }
    
    #if DEBUG
    private func updateDebugInfo() {
        let purchaseManager = PurchaseManager.shared
        if let nextReset = purchaseManager.nextResetDate {
            let timeInterval = nextReset.timeIntervalSince(Date())
            print("⏰ Time until reset: \(Int(timeInterval)) seconds")
            print("🎯 Remaining imports: \(purchaseManager.youtubeImportsRemaining)")
        }
    }
    #endif
    
    func refreshTimer() {
        currentTime = Date()
    }
    
    // Request the current time (without causing UI refresh)
    func getCurrentTime() -> Date {
        return Date()
    }
} 