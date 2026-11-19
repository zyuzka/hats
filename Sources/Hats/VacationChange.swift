import Foundation

struct VacationChange {
    let redraw: () -> Void
    let poll: () -> Void
    let sayItCouldNotSave: (Error) -> Void

    func apply(_ id: String, on: Bool, at now: Date, in store: AccountStore) {
        do {
            try store.setVacation(
                id,
                on: on,
                at: now
            )
            redraw()
            poll()
        } catch {
            redraw()
            sayItCouldNotSave(error)
        }
    }
}
