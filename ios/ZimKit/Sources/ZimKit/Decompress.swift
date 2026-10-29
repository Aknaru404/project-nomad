import Foundation
import libzstd

/// Cluster decompressors for the two codecs ZIM files use: zstd (current) and xz (older files).
enum Decompress {
    static func zstd(_ input: Data) throws -> Data {
        guard let dctx = ZSTD_createDCtx() else { throw ZimError.corrupt("cannot create zstd context") }
        defer { _ = ZSTD_freeDCtx(dctx) }

        let chunkSize = ZSTD_DStreamOutSize()
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        var output = Data()

        try input.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
            var inBuf = ZSTD_inBuffer(src: src.baseAddress, size: src.count, pos: 0)
            while true {
                var produced = 0
                var ret = 0
                buffer.withUnsafeMutableBytes { dst in
                    var outBuf = ZSTD_outBuffer(dst: dst.baseAddress, size: dst.count, pos: 0)
                    ret = ZSTD_decompressStream(dctx, &outBuf, &inBuf)
                    produced = outBuf.pos
                }
                if ZSTD_isError(ret) != 0 {
                    throw ZimError.corrupt("zstd: " + String(cString: ZSTD_getErrorName(ret)))
                }
                output.append(contentsOf: buffer[0..<produced])
                // ret == 0 means the frame is complete; otherwise stop once input is spent and the output buffer was not filled.
                if ret == 0 || (inBuf.pos == inBuf.size && produced < chunkSize) { break }
            }
        }
        return output
    }

    static func xz(_ input: Data) throws -> Data {
        // Apple's LZMA codec reads the xz container that ZIM uses.
        do {
            return try (input as NSData).decompressed(using: .lzma) as Data
        } catch {
            throw ZimError.corrupt("xz: \(error.localizedDescription)")
        }
    }
}
