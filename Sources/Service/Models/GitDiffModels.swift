//
//  GitDiffModels.swift
//
//
//  Created by ANPILOV Roman on 18.09.2024.
//

import Foundation

/// Тип изменения полученный из диффа гита
public enum DiffLineType: String, Sendable, Codable {
    case added
    case removed
    case unchanged
    case metadata
    case context
}

public enum FileChange: Hashable {
    case delete(path: String)
    case added(path: String)
    case modified(path: String)
    case renamed(path: String, newPath: String, isModified: Bool)
}

public struct DiffLine {
    let type: DiffLineType
    let content: String
    let lineNumberOriginal: Int?
    let lineNumberNew: Int?
}

public struct FileDiff {
    let oldFilePath: String
    let newFilePath: String
    let changes: [DiffLine]
}

extension Array where Element == FileChange {
    var pathsWithChangesInFile: [String] {
        self.compactMap {
            switch $0 {
            case .delete:
                return nil
            case .added(let path):
                return path
            case .modified(let path):
                return path
            case .renamed(_, let newPath, let isModified):
                if isModified {
                    return newPath
                }
                return nil
            }
        }
    }
}
