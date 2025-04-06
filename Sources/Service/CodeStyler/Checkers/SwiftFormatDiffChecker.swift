//
//  SwiftFormatService.swift
//  
//
//  Created by ANPILOV Roman on 18.09.2024.
//

import Foundation
import CommandExecutor

/// Сервис для проверки соответствия кода правилам SwiftFormat
public struct SwiftFormatDiffChecker: IFilesDiffChecker {
    private let swiftFormatBinaryPath: String
    private let swiftFormatRulesPath: String
    private let projectPath: String
    private let commandExecutor: CommandExecutor
    private let swiftFormatExclude: [String] = [
        "Localization.swift",
        "Bundle.swift"
    ]
    private let source = CodeStylerMessageSource(title: "SwiftFormat", description: "Rules from the .swiftformat file in the root of the project")
    
    public init(swiftFormatBinaryPath: String, swiftFormatRulesPath: String, projectPath: String, commandExecutor: CommandExecutor) {
        self.swiftFormatBinaryPath = swiftFormatBinaryPath
        self.swiftFormatRulesPath = swiftFormatRulesPath
        self.projectPath = projectPath
        self.commandExecutor = commandExecutor
    }

    
    public func checkDiff(
        _ changedFiles: [FileChange],
        _ filesDiff: [FileDiff]
    ) async throws -> [any ICodeStylerMessage] {
        var messages: [any ICodeStylerMessage] = []
        for file in filesDiff
            .filter ({ $0.newFilePath.suffix(6).contains(".swift") })
            .filter ({ !swiftFormatExclude.contains(URL(string: $0.newFilePath)?.lastPathComponent ?? "") }) {
            let result = CommandOutput()
            try? await commandExecutor.execute(
                textCommand: "\(swiftFormatBinaryPath) --config \(swiftFormatRulesPath) --lint ./\(file.newFilePath)",
                atPath: projectPath
            ) { line in
                await result.add(output: line.asString)
            }
            let output = await result.outputs.joined(separator: " ")
            let errorsForPath = try parseSwiftFormatOutput(
                file: file,
                terminalOutput: output
            )
            messages.append(contentsOf: errorsForPath)
        }
        return messages
    }
    
    private func parseSwiftFormatOutput(
        file: FileDiff,
        terminalOutput: String
    ) throws -> [CodeStyleErrorMessage] {
        let pattern = #"(.+?):(\d+):(\d+): error: (.+?)(?=\.\s*|$)"#
        var errors: [SwiftFormatError] = []
        let regex = try NSRegularExpression(pattern: pattern, options: [])
        let nsString = terminalOutput as NSString
        let results = regex.matches(in: terminalOutput, options: [], range: NSRange(location: 0, length: nsString.length))
        for match in results {
            let lineNumber = nsString.substring(with: match.range(at: 2))
            let columnNumber = nsString.substring(with: match.range(at: 3))
            let errorMessage = nsString.substring(with: match.range(at: 4))
            errors.append(
                .init(
                    filePath: file.newFilePath,
                    line: lineNumber,
                    column: columnNumber,
                    error: errorMessage,
                    typeOfChange: file.changes.first { $0.lineNumberNew == Int(lineNumber) }?.type ?? .unchanged
                )
            )
        }
        return errors.map {
            CodeStyleErrorMessage(
                message: $0.error,
                typeOfChange: $0.typeOfChange,
                line: $0.line,
                filePath: $0.filePath,
                source: source,
                level: .error
            )
        }
    }
}

private struct SwiftFormatError {
    let filePath: String
    let line: String
    let column: String
    let error: String
    let typeOfChange: DiffLineType
}
