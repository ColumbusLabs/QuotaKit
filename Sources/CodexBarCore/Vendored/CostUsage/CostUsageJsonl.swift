import Foundation

enum CostUsageJsonl {
    struct Line: Sendable {
        let bytes: Data
        let wasTruncated: Bool
    }

    static func scan(
        fileURL: URL,
        maxLineBytes: Int,
        prefixBytes: Int,
        onLine: (Line) -> Void) throws
    {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)

        var current = Data()
        current.reserveCapacity(4 * 1024)
        var lineBytes = 0
        var truncated = false

        func flushLine() {
            guard lineBytes > 0 else { return }
            let line = Line(bytes: current, wasTruncated: truncated)
            onLine(line)
            current.removeAll(keepingCapacity: true)
            lineBytes = 0
            truncated = false
        }

        while true {
            let chunk = try handle.read(upToCount: 256 * 1024) ?? Data()
            if chunk.isEmpty {
                flushLine()
                break
            }

            buffer.append(chunk)

            while true {
                guard let nl = buffer.firstIndex(of: 0x0A) else { break }
                let linePart = buffer[..<nl]
                buffer.removeSubrange(...nl)

                lineBytes += linePart.count
                if !truncated {
                    if lineBytes > maxLineBytes || lineBytes > prefixBytes {
                        truncated = true
                        current.removeAll(keepingCapacity: true)
                    } else {
                        current.append(contentsOf: linePart)
                    }
                }
                flushLine()
            }
        }
    }
}
