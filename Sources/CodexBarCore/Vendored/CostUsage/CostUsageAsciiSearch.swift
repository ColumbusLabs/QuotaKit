import Foundation
#if canImport(Musl)
import Musl
#elseif canImport(Glibc)
import Glibc
#else
import Darwin
#endif

extension Data {
    func containsAscii(_ needle: String) -> Bool {
        guard let n = needle.data(using: .utf8) else { return false }
        guard !n.isEmpty else { return self.range(of: n) != nil }
        guard n.count <= self.count else { return false }
        return self.withUnsafeBytes { haystack in
            n.withUnsafeBytes { pattern in
                guard let base = haystack.baseAddress, let needleBase = pattern.baseAddress else { return false }
                let first = Int32(pattern[0])
                let limit = haystack.count - pattern.count + 1
                var offset = 0
                while offset < limit {
                    guard let candidate = memchr(base.advanced(by: offset), first, limit - offset) else { return false }
                    if memcmp(candidate, needleBase, pattern.count) == 0 { return true }
                    offset = base.distance(to: UnsafeRawPointer(candidate)) + 1
                }
                return false
            }
        }
    }
}
