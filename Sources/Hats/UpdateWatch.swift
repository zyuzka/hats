import Foundation

final class UpdateWatch {
    private var timer: DispatchSourceTimer?

    func start(_ look: @escaping () -> Void) {
        stop()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + UpdateAnnouncement.firstCheckAfter,
            repeating: UpdateAnnouncement.interval
        )
        timer.setEventHandler { look() }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }
}
