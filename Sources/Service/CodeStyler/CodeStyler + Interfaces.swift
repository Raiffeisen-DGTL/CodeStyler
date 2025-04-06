//
//  ServiceInterfaces.swift
//  RaifMagicCore
//
//  Created by USOV Vasily on 03.12.2024.
//

import Foundation
import RaifMagicCore

// MARK: - Logger

/// Protocol for service logger
public protocol ICodeStylerLogger: Sendable {
    func log(message: String)
    func log(error: String)
}

// MARK: - DiffCheckers

/// Protocol for a service that parses a diff and returns errors found in it
public protocol IFilesDiffChecker: Sendable {
    func checkDiff(
        _ changedFiles: [FileChange],
        _ filesDiff: [FileDiff]
    ) async throws -> [any ICodeStylerMessage]
}

// MARK: - GitlabCheckers

/// Protocol for checking merge request
/// Used when running styler on CI
public protocol IGitlabMergeRequestChecker: Sendable {
    func check(mergeRequest: GitlabMergeRequest) async -> [any ICodeStylerMessage]
}
