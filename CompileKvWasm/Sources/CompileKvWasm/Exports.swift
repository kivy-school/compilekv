import Foundation

// Wasm can only pass numbers, so strings travel as (pointer, length) into
// linear memory. The host allocates with kv_alloc, calls kv_convert, then reads
// the result through kv_result_ptr/kv_result_len and releases it.

private nonisolated(unsafe) var resultBuffer: UnsafeMutableRawPointer?
private nonisolated(unsafe) var resultCount: Int32 = 0

private func storeResult(_ string: String) {
    freeResult()
    let utf8 = Array(string.utf8)
    guard !utf8.isEmpty else { return }
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: utf8.count, alignment: 1)
    utf8.withUnsafeBytes { buffer.copyMemory(from: $0.baseAddress!, byteCount: utf8.count) }
    resultBuffer = buffer
    resultCount = Int32(utf8.count)
}

private func freeResult() {
    resultBuffer?.deallocate()
    resultBuffer = nil
    resultCount = 0
}

private func string(from pointer: UnsafeRawPointer?, length: Int32) -> String {
    guard let pointer, length > 0 else { return "" }
    return String(decoding: UnsafeRawBufferPointer(start: pointer, count: Int(length)), as: UTF8.self)
}

@_expose(wasm, "kv_alloc")
@_cdecl("kv_alloc")
public func kv_alloc(_ size: Int32) -> UnsafeMutableRawPointer? {
    guard size > 0 else { return nil }
    return UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 1)
}

@_expose(wasm, "kv_dealloc")
@_cdecl("kv_dealloc")
public func kv_dealloc(_ pointer: UnsafeMutableRawPointer?, _ size: Int32) {
    pointer?.deallocate()
}

/// Returns 0 on success, 1 on failure. Either way the result buffer holds the
/// generated code or the error description.
@_expose(wasm, "kv_convert")
@_cdecl("kv_convert")
public func kv_convert(
    _ kvPointer: UnsafeRawPointer?,
    _ kvLength: Int32,
    _ pyPointer: UnsafeRawPointer?,
    _ pyLength: Int32
) -> Int32 {
    do {
        storeResult(try convert(
            kvSource: string(from: kvPointer, length: kvLength),
            pySource: string(from: pyPointer, length: pyLength)
        ))
        return 0
    } catch {
        storeResult("\(error)")
        return 1
    }
}

@_expose(wasm, "kv_result_ptr")
@_cdecl("kv_result_ptr")
public func kv_result_ptr() -> UnsafeMutableRawPointer? {
    resultBuffer
}

@_expose(wasm, "kv_result_len")
@_cdecl("kv_result_len")
public func kv_result_len() -> Int32 {
    resultCount
}

@_expose(wasm, "kv_result_free")
@_cdecl("kv_result_free")
public func kv_result_free() {
    freeResult()
}
