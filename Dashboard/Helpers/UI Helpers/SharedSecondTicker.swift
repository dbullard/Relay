import Combine
import Foundation

final class SharedSecondTicker {
    static let shared = SharedSecondTicker()

    @Published private var isPaused: Bool = false
    lazy var publisher: AnyPublisher<Date, Never> = {
        Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .combineLatest($isPaused)
            .filter { _, paused in !paused }
            .map { date, _ in date }
            .eraseToAnyPublisher()
    }()

    private init() {}

    func setPaused(_ paused: Bool) {
        isPaused = paused
    }
}
