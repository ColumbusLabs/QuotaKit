import Foundation

#if canImport(Glibc)
import Glibc

/// Swift's Glibc module does not import `<malloc.h>`.
@_silgen_name("malloc_trim")
private func glibcMallocTrim(_ pad: Int) -> Int32
#endif

enum CLIServeHeapTrimmer {
    static func start() -> (any DispatchSourceTimer)? {
        self.start(interval: .seconds(30), leeway: .seconds(5), onTrim: nil)
    }

    static func startForTesting(
        interval: DispatchTimeInterval,
        leeway: DispatchTimeInterval = .milliseconds(1),
        onTrim: @escaping @Sendable (Bool) -> Void) -> (any DispatchSourceTimer)?
    {
        self.start(interval: interval, leeway: leeway, onTrim: onTrim)
    }

    private static func start(
        interval: DispatchTimeInterval,
        leeway: DispatchTimeInterval,
        onTrim: (@Sendable (Bool) -> Void)?) -> (any DispatchSourceTimer)?
    {
        #if canImport(Glibc)
        // Cost refreshes can leave freed pages inside glibc arenas until the allocator trims them.
        let queue = DispatchQueue(label: "com.columbuslabs.quotakit.serve.heap-trimmer", qos: .utility)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: leeway)
        timer.setEventHandler {
            let releasedPages = glibcMallocTrim(0) != 0
            onTrim?(releasedPages)
        }
        timer.resume()
        return timer
        #else
        return nil
        #endif
    }
}
