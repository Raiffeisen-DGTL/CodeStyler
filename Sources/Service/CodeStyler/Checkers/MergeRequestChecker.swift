//
//  MergeRequestChecker.swift
//  RaifMagicCore
//
//  Created by USOV Vasily on 06.12.2024.
//

import RaifMagicCore

public final class MergeRequestChecker: IGitlabMergeRequestChecker {
    
    private let source = CodeStylerMessageSource(title: "Анализатор мердж-реквестов", description: "Правила по оформлениею merge-request")
    
    public init() {}
    
    public func check(mergeRequest: GitlabMergeRequest) async -> [any ICodeStylerMessage] {
        for scalar in mergeRequest.sourceBranch.unicodeScalars {
            if (0x0400...0x04FF).contains(Int(scalar.value)) {
                return [
                    MergeRequestErrorMessage(message: "Имя ветки не должно содержать символов на русском языке", source: source, level: .error)
                ]
            }
        }
        return []
    }
}
