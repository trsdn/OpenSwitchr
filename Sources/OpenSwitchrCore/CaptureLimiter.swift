import Foundation

/// Bounds how many captures run at once and lets the one the user is looking at
/// go first.
///
/// Unbounded concurrency against another process's window server does not go
/// faster, it goes wider, and the cost lands on the machine the user is trying
/// to work on. A request that is cancelled while it waits never starts and gives
/// its place up, so dismissing a panel does not leave a queue of captures
/// completing into a cache nobody will read this session.
public actor CaptureLimiter {

    public enum Priority: Int, Sendable {
        case normal = 0
        /// The tile the user is looking at.
        case high = 1
    }

    private struct Waiter {
        let id: UInt64
        let priority: Priority
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let maxConcurrent: Int
    private var running = 0
    private var waiters: [Waiter] = []
    private var nextID: UInt64 = 0

    public init(maxConcurrent: Int) {
        self.maxConcurrent = max(1, maxConcurrent)
    }

    /// How many requests are waiting for a slot.
    public var queuedCount: Int { waiters.count }

    /// Runs `work` once a slot is free, or returns `nil` without running it if
    /// the calling task is cancelled first.
    public func run<T: Sendable>(
        priority: Priority,
        _ work: @Sendable () async -> T
    ) async -> T? {
        guard await acquire(priority: priority) else { return nil }
        let result = await work()
        release()
        return result
    }

    private func acquire(priority: Priority) async -> Bool {
        if Task.isCancelled { return false }
        if running < maxConcurrent {
            running += 1
            return true
        }

        let id = nextID
        nextID += 1

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                // Checked here as well as before: the cancellation handler can
                // run before the waiter exists, and this closure runs on the
                // actor, so nothing can slip between this check and the append.
                if Task.isCancelled {
                    continuation.resume(returning: false)
                    return
                }
                waiters.append(Waiter(id: id, priority: priority, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: id) }
        }
    }

    private func cancelWaiter(id: UInt64) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(returning: false)
    }

    private func release() {
        running -= 1
        guard let next = nextWaiterIndex() else { return }
        running += 1
        waiters.remove(at: next).continuation.resume(returning: true)
    }

    /// Highest priority first, then the order the requests were made in.
    private func nextWaiterIndex() -> Int? {
        var best: Int?
        for (index, waiter) in waiters.enumerated() {
            guard let current = best else {
                best = index
                continue
            }
            if waiter.priority.rawValue > waiters[current].priority.rawValue { best = index }
        }
        return best
    }
}
