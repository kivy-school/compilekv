import Foundation

// MARK: - Wasm ABI
//
// WebAssembly can only pass numbers across the boundary, so strings travel as
// (pointer, length) pairs into the module's linear memory. The host allocates
// input buffers with `kv_alloc`, fills them, and calls `kv_convert`. The result
// (generated Python source, or an error message) is left in a module owned
// buffer that the host reads via `kv_result_ptr` / `kv_result_len` and releases
// with `kv_result_free`.

/// Buffer holding the outcome of the most recent `kv_convert` call.
///
/// The module is single threaded and driven one call at a time by the host, so
/// there is no concurrent access to guard against.
private nonisolated(unsafe) var resultBuffer: UnsafeMutableRawPointer?
private nonisolated(unsafe) var resultCount: Int32 = 0

private func storeResult(_ string: String) {
    freeResult()
    let utf8 = Array(string.utf8)
    let count = utf8.count
    guard count > 0 else { return }
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: count, alignment: 1)
    utf8.withUnsafeBytes { buffer.copyMemory(from: $0.baseAddress!, byteCount: count) }
    resultBuffer = buffer
    resultCount = Int32(count)
}

private func freeResult() {
    resultBuffer?.deallocate()
    resultBuffer = nil
    resultCount = 0
}

private func string(from pointer: UnsafeRawPointer?, length: Int32) -> String {
    guard let pointer, length > 0 else { return "" }
    let bytes = UnsafeRawBufferPointer(start: pointer, count: Int(length))
    return String(decoding: bytes, as: UTF8.self)
}

/// Allocate `size` bytes of linear memory for the host to write input into.
@_expose(wasm, "kv_alloc")
@_cdecl("kv_alloc")
public func kv_alloc(_ size: Int32) -> UnsafeMutableRawPointer? {
    guard size > 0 else { return nil }
    return UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 1)
}

/// Release a buffer previously handed out by `kv_alloc`.
@_expose(wasm, "kv_dealloc")
@_cdecl("kv_dealloc")
public func kv_dealloc(_ pointer: UnsafeMutableRawPointer?, _ size: Int32) {
    pointer?.deallocate()
}

/// Convert a KV source string into Python class source.
///
/// `pyPointer` / `pyLength` describe the current contents of the matching `.py`
/// file and may be empty when there is none.
///
/// Returns 0 on success and 1 on failure; in both cases the result buffer holds
/// the generated code or the error description respectively.
@_expose(wasm, "kv_convert")
@_cdecl("kv_convert")
public func kv_convert(
    _ kvPointer: UnsafeRawPointer?,
    _ kvLength: Int32,
    _ pyPointer: UnsafeRawPointer?,
    _ pyLength: Int32
) -> Int32 {
    let kvSource = string(from: kvPointer, length: kvLength)
    let pySource = string(from: pyPointer, length: pyLength)
    do {
        storeResult(try convert(kvSource: kvSource, pySource: pySource))
        return 0
    } catch {
        storeResult("\(error)")
        return 1
    }
}

/// Pointer to the result of the most recent `kv_convert` call.
@_expose(wasm, "kv_result_ptr")
@_cdecl("kv_result_ptr")
public func kv_result_ptr() -> UnsafeMutableRawPointer? {
    resultBuffer
}

/// Length in bytes of the result of the most recent `kv_convert` call.
@_expose(wasm, "kv_result_len")
@_cdecl("kv_result_len")
public func kv_result_len() -> Int32 {
    resultCount
}

/// Release the result buffer once the host has copied it out.
@_expose(wasm, "kv_result_free")
@_cdecl("kv_result_free")
public func kv_result_free() {
    freeResult()
}
