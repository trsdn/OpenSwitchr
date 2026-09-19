import OpenSwitchrCore

/// The performance budgets `openswitchr-diag --check-budgets` enforces.
///
/// One file, next to the harness that produces the numbers. A budget is raised
/// deliberately, in the commit that justifies raising it, and never nudged
/// until a run passes.
///
/// **Every one of these is wall-clock and therefore machine-dependent.** They
/// need the Accessibility grant, real windows, and a machine that is not sharing
/// a core with three other jobs, so this is a pre-release check that belongs in
/// `RELEASE_CHECKLIST.md`, never a hosted CI gate: a wall-clock budget on
/// someone else's laptop is noise. The limits are set with generous headroom
/// over what Apple Silicon measured, so they catch a regression of the kind that
/// matters — a rebuild that stops being cheap — not scheduler jitter.
enum Budgets {

    static let coldRebuild = "Cold index rebuild"
    static let warmRebuild = "Warm index rebuild, concurrent, mean"
    static let coldThumbnails = "Cold thumbnails, 8 in parallel"
    static let cacheHits = "Thumbnail cache hits, 8"

    static let all: [PerformanceBudget] = [
        // README: cold builds ~160-240 ms, off the main thread.
        PerformanceBudget(name: coldRebuild, limitMilliseconds: 1_000),
        // README budget: < 100 ms; measured ~9-15 ms.
        PerformanceBudget(name: warmRebuild, limitMilliseconds: 100),
        // README: ~340-540 ms, streamed into the UI.
        PerformanceBudget(name: coldThumbnails, limitMilliseconds: 2_000),
        // README: < 0.1 ms each.
        PerformanceBudget(name: cacheHits, limitMilliseconds: 5)
    ]
}
