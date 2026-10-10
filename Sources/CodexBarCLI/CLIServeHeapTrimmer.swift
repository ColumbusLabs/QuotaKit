import Foundation

#if canImport(Glibc)
import Glibc

/// Swift's Glibc module does not import `<malloc.h>`.
@_silgen_name("malloc_trim")
private func glibcMallocTrim(_ pad: Int) -> Int32
#endif

enum CLIServeHeapTrimmer {
    static func start() -> (any DispatchSourceTimer)? {
        #if canImport(Glibc)
        // Cost refreshes can leave freed pages inside glibc arenas until the allocator trims them.
        let queue = DispatchQueue(label: "com.columbuslabs.quotakit.serve.heap-trimmer", qos: .utility)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 30, repeating: 30, leeway: .seconds(5))
        timer.setEventHandler { _ = glibcMallocTrim(0) }
        timer.resume()
        return timer
        #else
        return nil
        #endif
    }
}
