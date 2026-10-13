import Compression
import Foundation
import libzstd

/// Decodes HTTP response bodies stored with their `content-encoding` (as Chromium's cache keeps them).
public enum HTTPBodyDecoder {
    /// Upper bound for decoded bodies; usage responses are a few kilobytes.
    static let maximumDecodedSize = 2 * 1024 * 1024

    public static func decode(_ body: Data, contentEncoding: String?) -> Data? {
        switch contentEncoding?.lowercased().trimmingCharacters(in: .whitespaces) {
        case nil, "", "identity": return body
        case "zstd": return zstd(body)
        case "br": return apple(body, algorithm: COMPRESSION_BROTLI)
        case "gzip": return gzip(body)
        case "deflate": return apple(body, algorithm: COMPRESSION_ZLIB)
        default: return nil
        }
    }

    /// Streaming decode with the official libzstd, so frames without a declared size also work.
    public static func zstd(_ input: Data) -> Data? {
        guard let context = ZSTD_createDCtx() else { return nil }
        defer { ZSTD_freeDCtx(context) }
        var output = Data()
        let chunkSize = ZSTD_DStreamOutSize()
        var chunk = [UInt8](repeating: 0, count: chunkSize)
        return input.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Data? in
            var inBuffer = ZSTD_inBuffer(src: raw.baseAddress, size: raw.count, pos: 0)
            while true {
                let (result, produced) = chunk.withUnsafeMutableBytes { out -> (Int, Int) in
                    var outBuffer = ZSTD_outBuffer(dst: out.baseAddress, size: out.count, pos: 0)
                    let code = ZSTD_decompressStream(context, &outBuffer, &inBuffer)
                    return (ZSTD_isError(code) != 0 ? -1 : code, outBuffer.pos)
                }
                guard result >= 0 else { return nil }
                output.append(contentsOf: chunk[0..<produced])
                guard output.count <= maximumDecodedSize else { return nil }
                if result == 0 { return output }                       // frame complete
                if inBuffer.pos >= inBuffer.size && produced < chunkSize { return nil }  // truncated
            }
        }
    }

    static func gzip(_ input: Data) -> Data? {
        // RFC 1952 header: 10 bytes, optional FEXTRA / FNAME / FCOMMENT / FHCRC.
        guard input.count > 18, input[input.startIndex] == 0x1F, input[input.startIndex + 1] == 0x8B else { return nil }
        let bytes = [UInt8](input)
        let flags = bytes[3]
        var offset = 10
        if flags & 0x04 != 0, offset + 2 <= bytes.count {
            offset += 2 + Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
        }
        for flag in [UInt8(0x08), 0x10] where flags & flag != 0 {
            while offset < bytes.count && bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 { offset += 2 }
        guard offset < bytes.count - 8 else { return nil }
        return apple(Data(bytes[offset..<(bytes.count - 8)]), algorithm: COMPRESSION_ZLIB)
    }

    static func apple(_ input: Data, algorithm: compression_algorithm) -> Data? {
        guard !input.isEmpty else { return Data() }
        let capacity = maximumDecodedSize
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { destination.deallocate() }
        let written = input.withUnsafeBytes { raw in
            compression_decode_buffer(destination, capacity, raw.bindMemory(to: UInt8.self).baseAddress!, input.count,
                                      nil, algorithm)
        }
        return written > 0 ? Data(bytes: destination, count: written) : nil
    }
}
