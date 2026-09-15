//
//  NameCounter.swift
//  KvToPyClass
//
//  Created by CodeBuilder on 12/09/2026.
//

/// Supplies stable, unique suffixes for generated variable names.
///
/// Numbering restarts for each class so adding a widget to one rule does
/// not renumber the rest of the file.
final class NameCounter {
    private var next = 0

    func take() -> Int {
        next += 1
        return next
    }

    func reset() {
        next = 0
    }
}
