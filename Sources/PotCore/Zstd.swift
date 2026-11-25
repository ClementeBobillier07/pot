import Foundation
import CZstd

/// Streaming Zstandard decoding for archived Codex rollouts (`*.jsonl.zst`).
/// Uses the vendored official decoder (zstd 1.5.7, BSD); no runtime dependency or subprocess.
enum ZstdStream {
    enum Failure: Error { case corrupt, truncated, tooLarge }

    /// Streams decompressed bytes to `body`. Window size is bounded by libzstd's default
    /// (`ZSTD_WINDOWLOG_LIMIT_DEFAULT`, 128 MiB) and total output by `maximumOutput`.
    static func decompress(_ url: URL, maximumOutput: UInt64, _ body: (UnsafeRawBufferPointer) -> Void) throws {
        guard let stream = ZSTD_createDStream() else { throw Failure.corrupt }
        defer { ZSTD_freeDStream(stream) }
        guard ZSTD_isError(ZSTD_initDStream(stream)) == 0 else { throw Failure.corrupt }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let outputCapacity = ZSTD_DStreamOutSize()
        let output = UnsafeMutableRawPointer.allocate(byteCount: outputCapacity, alignment: 16)
        defer { output.deallocate() }
        var produced: UInt64 = 0
        var pending = 0 // 0 means the last frame ended exactly.
        var sawInput = false
        while true {
            let finished: Bool = try autoreleasepool {
            let chunk = try file.read(upToCount: ZSTD_DStreamInSize()) ?? Data()
            if chunk.isEmpty { return true }
            sawInput = true
            try chunk.withUnsafeBytes { raw in
                var input = ZSTD_inBuffer(src: raw.baseAddress, size: raw.count, pos: 0)
                repeat {
                    var out = ZSTD_outBuffer(dst: output, size: outputCapacity, pos: 0)
                    let result = ZSTD_decompressStream(stream, &out, &input)
                    if ZSTD_isError(result) != 0 { throw Failure.corrupt }
                    pending = result
                    produced += UInt64(out.pos)
                    if produced > maximumOutput { throw Failure.tooLarge }
                    if out.pos > 0 { body(UnsafeRawBufferPointer(start: output, count: out.pos)) }
                    if input.pos >= input.size && out.pos < out.size { break }
                } while true
            }
            return false
            }
            if finished { break }
        }
        if sawInput && pending != 0 { throw Failure.truncated }
    }
}
