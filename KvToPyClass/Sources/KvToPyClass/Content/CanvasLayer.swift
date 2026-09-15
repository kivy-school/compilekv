//
//  CanvasLayer.swift
//  KvToPyClass
//

import KvParser

/// The three canvases a widget has.
enum CanvasLayer: CaseIterable {
    case before, main, after
    
    /// The attribute under `canvas`, or nil for the canvas itself.
    var attribute: String? {
        switch self {
        case .before: "before"
        case .main: nil
        case .after: "after"
        }
    }
    
    /// The layers a body draws on, in order, skipping the empty ones.
    static func layers(of body: KvBody) -> [(layer: CanvasLayer, canvas: KvCanvas)] {
        [(before, body.canvasBefore), (main, body.canvas), (after, body.canvasAfter)]
            .compactMap { layer, canvas in canvas.map { (layer, $0) } }
    }
}
