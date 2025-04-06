//
//  RegexCheckerService.swift
//
//
//  Created by ANPILOV Roman on 18.09.2024.
//

import Foundation
import SwiftSyntax
import SwiftParser

public final class RegexCheckerService: IFilesDiffChecker {
    
    private let source = CodeStylerMessageSource(title: "CommunityFormat", description: "Внутренние правила комьюнити по оформлению/документированию кода")
    
    private let projectPath: String
    
    public init(projectPath: String) {
        self.projectPath = projectPath
    }
    
    public func checkDiff(
        _ changedFiles: [FileChange],
        _ filesDiff: [FileDiff]
    ) async throws -> [any ICodeStylerMessage] {
        let syntaxMessages: [any ICodeStylerMessage] = filesDiff.filter { $0.newFilePath.contains(".swift") }.compactMap { file -> [any ICodeStylerMessage] in
            let url = URL(fileURLWithPath: "\(projectPath)/\(file.newFilePath)")
            guard let source = try? String(contentsOf: url, encoding: .utf8)
            else {
                assertionFailure("Не найден файл по пути - \(url.path())");
                return []
            }
            let parsedAST = Parser.parse(source: source)
            let docChecker = DocumentationChecker(viewMode: .all) // Проверка на наличие документации
            docChecker.source = source
            docChecker.walk(parsedAST)
            let messages: [any ICodeStylerMessage] = (
                docChecker.messages
            )
                .compactMap { message in
                    guard let diffLine = file.changes.first (
                        where: { $0.lineNumberNew == message.1 || $0.lineNumberOriginal == message.1 }
                    )
                    else { return nil }
                    return CodeStyleErrorMessage(
                        message: message.0,
                        typeOfChange: diffLine.type,
                        line: String(message.1),
                        filePath: file.newFilePath,
                        source: self.source,
                        level: .error
                    )
                }
            return messages
        }
            .flatMap { $0 }
        
        return syntaxMessages
    }
    
    
    private func convertRegexToLinterMessage(
        _ regexResult: [CheckRegex],
        message: String
    ) -> [any ICodeStylerMessage] {
        regexResult.map { file in
            file.matchedLines.map {
                let threadBody = CodeStyleErrorMessage(
                    message: message,
                    typeOfChange: $0.type,
                    line: String($0.lineNumberNew ?? $0.lineNumberOriginal ?? 0),
                    filePath: file.path,
                    source: source,
                    level: .error
                )
                return threadBody
            }
        }.flatMap { $0 }
    }
    
    private func filesMatchToRegex(
        regex: String,
        _ filesDiff: [FileDiff],
        _ diffLineTypes: [DiffLineType] = [.added]
    ) throws -> [CheckRegex] {
        guard let regex = try? NSRegularExpression(
            pattern: regex,
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        )
        else { fatalError("Not valid regex") }
        return filesDiff.compactMap {
            let newLines = $0.changes.filter { diffLineTypes.contains($0.type) }
            let matchedLines = newLines.compactMap {
                let range = NSRange(location: 0, length: $0.content.utf16.count)
                let match = regex.firstMatch(in: $0.content, options: [], range: range)
                return match != nil ? $0 : nil
            }
            return matchedLines.isEmpty ? nil : CheckRegex(
                path: $0.newFilePath,
                matchedLines: matchedLines
            )
        }
    }
}

private struct CheckRegex {
    let path: String
    let matchedLines: [DiffLine]
}

extension AbsolutePosition {
    func lineAndColumn(lines: [String]) -> (Int, Int) {
        var byteOffset = self.utf8Offset
        var lineNumber = 0
        var columnNumber = 0

        for (index, line) in lines.enumerated() {
            let lineLength = line.utf8.count + 1
            if byteOffset < lineLength {
                lineNumber = index + 1
                columnNumber = byteOffset + 1
                break
            }
            byteOffset -= lineLength
        }
        return (lineNumber, columnNumber)
    }
}
