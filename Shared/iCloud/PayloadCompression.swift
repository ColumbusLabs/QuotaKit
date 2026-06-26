import Compression
import Foundation

/// zlib compression helpers for per-provider CKRecord payloads.
///
/// Wire format: 4-byte little-endian UInt32 containing the **uncompressed** byte
/// count, followed by the zlib-deflated bytes. The size prefix is required
/// because `compression_decode_buffer` needs a pre-sized destination buffer.
///
/// Measured ~10× reduction on realistic per-provider JSON (dense utilization
/// history dominates; zlib exploits the repetitive date/double structure).
public enum PayloadCompression {
    public enum Error: Swift.Error, Equatable {
        case compressionFailed
        case malformedHeader
        case payloadTooLarge
        case decompressionFailed
        case sizeMismatch
    }

    public static let maxDecompressedSize = 1_048_576

    private static let headerSize = 4

    public static func compress(_ data: Data) throws -> Data {
        guard !data.isEmpty else {
            // Preserve empty-in → empty-out so callers can round-trip without a
            // special case; just emit a zero-length header + no body.
            var header = UInt32(0).littleEndian
            return Data(bytes: &header, count: self.headerSize)
        }

        let originalCount = data.count
        guard originalCount <= Self.maxDecompressedSize else { throw Error.payloadTooLarge }

        // zlib can inflate small or incompressible input; 1.5× + 64 covers the
        // worst-case envelope without heap churn on the typical path.
        let destinationCapacity = max(originalCount + 64, originalCount * 3 / 2)
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationCapacity)
        defer { destination.deallocate() }

        let compressedCount = data.withUnsafeBytes { raw -> Int in
            guard let sourcePtr = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_encode_buffer(
                destination, destinationCapacity,
                sourcePtr, originalCount,
                nil, COMPRESSION_ZLIB)
        }
        guard compressedCount > 0 else { throw Error.compressionFailed }

        var header = UInt32(originalCount).littleEndian
        var output = Data(capacity: headerSize + compressedCount)
        output.append(Data(bytes: &header, count: self.headerSize))
        output.append(destination, count: compressedCount)
        return output
    }

    public static func decompress(_ data: Data) throws -> Data {
        guard data.count >= self.headerSize else { throw Error.malformedHeader }

        let originalCount: Int = data.prefix(self.headerSize).withUnsafeBytes { raw in
            Int(UInt32(littleEndian: raw.load(as: UInt32.self)))
        }
        if originalCount == 0 {
            return Data()
        }
        guard originalCount <= Self.maxDecompressedSize else { throw Error.payloadTooLarge }
        guard data.count > self.headerSize else { throw Error.malformedHeader }

        let body = data.suffix(from: self.headerSize)
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: originalCount)
        defer { destination.deallocate() }

        let decompressedCount = body.withUnsafeBytes { raw -> Int in
            guard let sourcePtr = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_decode_buffer(
                destination, originalCount,
                sourcePtr, body.count,
                nil, COMPRESSION_ZLIB)
        }
        guard decompressedCount > 0 else { throw Error.decompressionFailed }
        guard decompressedCount == originalCount else { throw Error.sizeMismatch }

        return Data(bytes: destination, count: decompressedCount)
    }
}
