import Foundation

/// A fair, reentrancy-free async mutex.
///
/// `InMemoryStore` is an actor, so each of its methods is individually
/// serialised — but a transaction spans several of them with suspension points
/// in between. This lock is what gives the whole body exclusivity, standing in
/// for SQLite's write lock.
actor AsyncLock {
    private var isHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard isHeld else {
            isHeld = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            isHeld = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
