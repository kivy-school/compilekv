// The wasm module is built as a reactor: the host instantiates it, calls
// `_initialize`, and then drives the functions exported from `Exports.swift`.
// SwiftPM still requires an entry point for an executable target, so this stays
// empty on purpose.
