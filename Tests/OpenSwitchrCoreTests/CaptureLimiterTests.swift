import Foundation
import Testing

@testable import OpenSwitchrCore

/// Lets a test hold a job open until it says so.
private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

private actor Recorder {
    private(set) var started: [String] = []
    private var running = 0
    private(set) var peak = 0

    func began(_ name: String) {
        started.append(name)
        running += 1
        peak = max(peak, running)
    }

    func ended() { running -= 1 }
}

private func waitUntilQueued(_ limiter: CaptureLimiter, _ count: Int) async {
    for _ in 0..<2000 {
        if await limiter.queuedCount >= count { return }
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(1))
    }
}

@Suite("CaptureLimiter")
struct CaptureLimiterTests {

    @Test("It returns the work's result")
    func returnsResult() async {
        let limiter = CaptureLimiter(maxConcurrent: 2)
        let value = await limiter.run(priority: .normal) { 42 }
        #expect(value == 42)
    }

    @Test("Never more than the cap run at once, however many are asked for")
    func neverExceedsTheCap() async {
        let limiter = CaptureLimiter(maxConcurrent: 3)
        let recorder = Recorder()

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<20 {
                group.addTask {
                    _ = await limiter.run(priority: .normal) {
                        await recorder.began("job\(index)")
                        try? await Task.sleep(for: .milliseconds(5))
                        await recorder.ended()
                    }
                }
            }
        }

        #expect(await recorder.peak <= 3)
        #expect(await recorder.started.count == 20)
    }

    @Test("A high-priority request jumps ahead of normal ones already waiting")
    func highPriorityGoesFirst() async {
        let limiter = CaptureLimiter(maxConcurrent: 1)
        let gate = Gate()
        let recorder = Recorder()

        let blocker = Task {
            await limiter.run(priority: .normal) {
                await recorder.began("blocker")
                await gate.wait()
                await recorder.ended()
            }
        }
        await waitUntilQueued(limiter, 0)
        while await recorder.started.isEmpty { await Task.yield() }

        var tasks: [Task<Void?, Never>] = []
        for (name, priority) in [("a", CaptureLimiter.Priority.normal), ("b", .normal), ("selected", .high)] {
            tasks.append(Task {
                await limiter.run(priority: priority) {
                    await recorder.began(name)
                    await recorder.ended()
                }
            })
            await waitUntilQueued(limiter, tasks.count)
        }

        await gate.open()
        _ = await blocker.value
        for task in tasks { _ = await task.value }

        // The selected tile was asked for last and ran first; the two normal
        // ones keep the order they were asked in.
        #expect(await recorder.started == ["blocker", "selected", "a", "b"])
    }

    @Test("A request cancelled while waiting never runs and reports that it did not")
    func cancelledWaiterNeverRuns() async {
        let limiter = CaptureLimiter(maxConcurrent: 1)
        let gate = Gate()
        let recorder = Recorder()

        let blocker = Task {
            await limiter.run(priority: .normal) {
                await recorder.began("blocker")
                await gate.wait()
                await recorder.ended()
            }
        }
        while await recorder.started.isEmpty { await Task.yield() }

        let waiting = Task {
            await limiter.run(priority: .normal) {
                await recorder.began("cancelled")
            }
        }
        await waitUntilQueued(limiter, 1)
        waiting.cancel()
        let result = await waiting.value

        await gate.open()
        _ = await blocker.value

        #expect(result == nil)
        #expect(await recorder.started == ["blocker"])
        #expect(await limiter.queuedCount == 0)
    }

    @Test("A cancelled request does not leak its slot")
    func cancelledDoesNotLeakASlot() async {
        let limiter = CaptureLimiter(maxConcurrent: 1)
        let gate = Gate()
        let recorder = Recorder()

        let blocker = Task {
            await limiter.run(priority: .normal) {
                await recorder.began("blocker")
                await gate.wait()
            }
        }
        while await recorder.started.isEmpty { await Task.yield() }

        let waiting = Task { await limiter.run(priority: .normal) { 1 } }
        await waitUntilQueued(limiter, 1)
        waiting.cancel()
        _ = await waiting.value
        await gate.open()
        _ = await blocker.value

        // If the cancelled waiter had kept the slot this would hang.
        let after = await limiter.run(priority: .normal) { "ran" }
        #expect(after == "ran")
    }
}
