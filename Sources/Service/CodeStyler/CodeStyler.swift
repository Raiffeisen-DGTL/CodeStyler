//
//  Linter.swift
//
//
//  Created by ANPILOV Roman on 31.07.2024.
//

import Foundation
import CommandExecutor
import RaifMagicCore

/// Service for checking modified code according to various rules
/// Service collects diff (file changes) and transfers them to "checkers", each of which generates messages about errors found
/// Also performs other checks depending on the selected operating mode and the transferred "checkers"
public final class CodeStylerService: Sendable {
    
    private let commandExecutor: CommandExecutor
    private let logger: any ICodeStylerLogger
    
    /// Create service
    /// - Parameters:
    ///   - commandExecutor: Executor of shell operations
    ///   - logger: Logger
    ///   - excludeFilesWithNameContaints: Exclude from analysis files containing the specified strings in their names
    ///   - mode: Service operating mode
    public init(commandExecutor: CommandExecutor, logger: ICodeStylerLogger) {
        self.logger = logger
        self.commandExecutor = commandExecutor
    }
    
    
    // TODO: Передавать сюда MergeRequest, грузить его раньше. Тогда не нужен будет gitlabService
    public func analyze(gitlabConfiguration: GitlabConfiguration, projectPath: String) async throws -> [any ICodeStylerMessage] {
        var mergeRequestMessages: [any ICodeStylerMessage] = []
        for checker in gitlabConfiguration.mergeRequestCheckers {
            mergeRequestMessages += await checker.check(mergeRequest: gitlabConfiguration.mergeRequest)
        }
        
        let messages = try await fetchMessages(
            targetBranch: gitlabConfiguration.mergeRequest.targetBranch,
            sourceBranch: gitlabConfiguration.mergeRequest.sourceBranch,
            diffSource: gitlabConfiguration.filesDiffSource,
            diffCheckers: gitlabConfiguration.filesDiffCheckers,
            excludeFiles: gitlabConfiguration.excludeFilesWithNameContaints,
            isCI: true,
            projectPath
        )
        return mergeRequestMessages + messages
    }
    
    public func analyze(localConfiguration: LocalConfiguration, projectPath: String) async throws -> [any ICodeStylerMessage] {
        guard let sourceBranchName = try? await commandExecutor.execute(
           сommandWithSingleOutput: "git branch --show-current",
           atPath: projectPath
        ) else {
            throw ServiceError.notFindSourceBranch
        }
        let messages = try await fetchMessages(
            targetBranch: localConfiguration.targetGitBranch,
            sourceBranch: sourceBranchName,
            diffSource: localConfiguration.filesDiffSource,
            diffCheckers: localConfiguration.filesDiffCheckers,
            excludeFiles: localConfiguration.excludeFilesWithNameContaints,
            isCI: false,
            projectPath
        )
        logMessagesIfNeeded(messages)
        return messages
    }
    
    // MARK: - Analyzer for CI
    
    public func analyzeMergeRequest(projectPath: String,
                                    diffSource: CodeStylerService.FilesDiffSource,
                                    diffCheckers: [any IFilesDiffChecker],
                                    mergeRequestCheckers: [any IGitlabMergeRequestChecker],
                                    gitlabService: GitlabAPIService
    ) async throws -> [any ICodeStylerMessage] {
        []
    }
    
    func emitErrorsInCIFormat(
        _ messages: [any ICodeStylerMessage],
        _ mergeRequest: GitlabMergeRequest,
        gitlabService: GitlabAPIService,
        path: String
    ) async throws {

    }
    
    public func sendThroughtCFPort(messages sourceMessages: [any ICodeStylerMessage], portID: String, trySeconds: TimeInterval) async throws {
        logger.log(message: "Try to send messages throught CFPort - \(portID)")
        let messages: [CodeStyleMessageDTO] = sourceMessages.compactMap {
            if let item = $0 as? CodeStyleErrorMessage {
                CodeStyleMessageDTO(base: .code(item))
            } else if let item = $0 as? FileErrorMessage {
                CodeStyleMessageDTO(base: .file(item))
            } else { nil }
        }

        if let data = try? JSONEncoder().encode(messages) {
            let endTimestamp = CFAbsoluteTimeGetCurrent() + trySeconds
            var didSend = false
            while CFAbsoluteTimeGetCurrent() < endTimestamp && didSend == false {
                logger.log(message: "Try to create CFPort with ID \(portID)")
                guard let messagePort = CFMessagePortCreateRemote(nil, portID as CFString) else {
                    try await Task.sleep(for: .seconds(1))
                    continue
                }
                var unmanagedData: Unmanaged<CFData>? = nil
                CFMessagePortSendRequest(
                    messagePort,
                    0,
                    data as CFData, 3.0, 3.0,
                    CFRunLoopMode.defaultMode.rawValue,
                    &unmanagedData
                )
                logger.log(message: "Messages was send")
                didSend = true
            }
        }
    }
    
    public func receiveMessagesFromCFPort(portID: String) async throws -> [any ICodeStylerMessage] {
        logger.log(message: "Trying to get message from CodeStyler CFPort - \(portID)")

        let connectionContainer = ReceiveConnectionContainer()
        let continuationContainer = ContinuationContainer(continuation: nil)
        return try await withTaskCancellationHandler {
            do {
                let messages: [any ICodeStylerMessage] = try await withCheckedThrowingContinuation { continuation in
                    continuationContainer.continuation = continuation
                    let info = Unmanaged.passUnretained(continuationContainer).toOpaque()
                    var context = CFMessagePortContext(version: 0, info: info, retain: nil, release: nil, copyDescription: nil)
                    if let messagePort = CFMessagePortCreateLocal(nil, portID as CFString, callback, &context, nil),
                       let source = CFMessagePortCreateRunLoopSource(nil, messagePort, 0){
                        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
                        connectionContainer.port = messagePort
                        connectionContainer.runLoop = source
                    }
                }
                stopReceiveFromCFPort(port: connectionContainer.port, runLoop: connectionContainer.runLoop)
                logger.log(error: "Message received successfully")
                return messages
            } catch {
                logger.log(error: "Error while waiting for data - \(error.localizedDescription)")
                stopReceiveFromCFPort(port: connectionContainer.port, runLoop: connectionContainer.runLoop)
                throw error
            }
        } onCancel: {
            // TODO: Theoretically, there may be a crash here or in the callback property due to repeated access to continuation. Is it better to choose an actor as continuationContainer?
            guard let continuation = continuationContainer.continuation else { return }
            continuationContainer.continuation = nil
            continuation.resume(throwing: ServiceError.ReceiveError.cancellationError)
        }
    }
    
    private func stopReceiveFromCFPort(port: CFMessagePort?, runLoop: CFRunLoopSource?) {
        if let runLoop {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoop, .defaultMode)
        }
        if let port {
            CFMessagePortInvalidate(port)
        }
    }
    
    private let callback: CFMessagePortCallBack = { messagePort, messageId, cfData, info in
        guard let info,
              let dataRecived = cfData as Data?
        else { return nil }
        
        let continuationContainer = Unmanaged<ContinuationContainer>.fromOpaque(info).takeUnretainedValue()
        
        if let decodedData = try? JSONDecoder().decode([CodeStyleMessageDTO].self, from: dataRecived) {
            let decodedMessages = decodedData.map { dto -> any ICodeStylerMessage in
                switch dto.base {
                case .code(let codeStyleMessage):
                    codeStyleMessage
                case .file(let projectStyleMessage):
                    projectStyleMessage
                }
            }
            guard let continuation = continuationContainer.continuation else { return nil }
            continuationContainer.continuation = nil
            continuation.resume(returning: decodedMessages)
        }
        return nil
    }
    
    private func logMessagesIfNeeded(_ messages: [any ICodeStylerMessage]) {
        guard messages.isEmpty == false else { return }
        var logError = "FINDED ERRORS"
        messages.forEach { item in
            if let item = item as? CodeStyleErrorMessage {
                logError += "\n\t\(item.filePath):\(item.line): message: \(item.message)"
            } else if let item = item as? FileErrorMessage {
                logError += "\n\t\(item.filePath): message: \(item.message)"
            }
        }
        logger.log(message: logError)
    }
    
    private func fetchMessages(
        targetBranch: String,
        sourceBranch: String,
        diffSource: CodeStylerService.FilesDiffSource,
        diffCheckers: [any IFilesDiffChecker],
        excludeFiles: [String],
        isCI: Bool,
        _ path: String
    ) async throws -> [any ICodeStylerMessage] {
        let changedFiles = try await getChangedFiles(
            path: path,
            targetBranch: targetBranch,
            sourceBranch: sourceBranch,
            isCIPipe: isCI,
            diffSource: diffSource
        )
        let diffForChangedFiles = try await getDiffForChangedFiles(
            path: path,
            changedFiles: changedFiles,
            targetBranch: targetBranch,
            sourceBranch: sourceBranch,
            excludeFiles: excludeFiles,
            isCIPipe: isCI
        )
        // @MainActor and MessagesContainer are needed because `reduce` causes a yellow warning
        // https://forums.swift.org/t/use-withthrowingtaskgroup-within-actor-leads-to-non-sendable-type-inout-throwingtaskgroup-void-any-error-async-throws-compilation-warning/60271/17
        return try await withThrowingTaskGroup(of: [any ICodeStylerMessage].self) { @MainActor taskGroup in
            let container = MessagesContainer()
            diffCheckers.forEach { checker in
                taskGroup.addTask {
                    try await checker.checkDiff(changedFiles, diffForChangedFiles)
                }
            }
            // workaround
            for try await messages in taskGroup {
                container.messages += messages
            }
            return container.messages
            // TODO: Replace with this when they fix it in Swift
//            return try await taskGroup.reduce(into: []) { $0.append(contentsOf: $1) }
        }
        .filter { message in
            guard let message = message as? CodeStyleErrorMessage,
                  let diffFile = diffForChangedFiles.first(where: { $0.newFilePath == message.filePath })
            else { return true }
            return diffFile.changes.contains(
                where: { $0.lineNumberNew == Int(message.line) || $0.lineNumberOriginal == Int(message.line) }
            )
        }
    }
    
    func getDiffForChangedFiles(
        path: String,
        changedFiles: [FileChange],
        targetBranch: String,
        sourceBranch: String,
        excludeFiles: [String],
        isCIPipe: Bool
    ) async throws -> [FileDiff] {
        var filesChanged: [FileDiff] = []
        
        let filteredPaths = changedFiles.pathsWithChangesInFile.filter { path in
            let components = path.split(separator: "/").map(String.init)
            return !excludeFiles.contains { exclude in
                if exclude.contains("/") {
                    path.hasPrefix(exclude)
                } else {
                    components.contains(exclude)
                }
            }
        }

        for file in filteredPaths {
            var stringDiff = try await commandExecutor.execute(
                сommandWithSingleOutput: "git diff  \(isCIPipe ? "origin/" : "")\(targetBranch)...\(isCIPipe ? "origin/" : "")\(sourceBranch) \(file) | sed 's/$/ @delimiter@/'",
                atPath: path
            )
            if stringDiff.isEmpty {
                stringDiff = try await commandExecutor.execute(
                    сommandWithSingleOutput: "git diff --cached \(file) | sed 's/$/ @delimiter@/'",
                    atPath: path
                )
            }
            filesChanged.append(contentsOf: parseDiffLineByLine(diff: stringDiff))
        }
        return filesChanged
    }
    
    func getChangedFiles(
        path: String,
        targetBranch: String,
        sourceBranch: String,
        isCIPipe: Bool,
        diffSource: CodeStylerService.FilesDiffSource
    ) async throws -> [FileChange] {
        var filesChanges: Set<FileChange> = []
        
        let gitDiffCommandBuilder: (String) -> String = { diffCommand in
            """
            while read STATUS ADDR
            do
                echo "%$ADDR% #$STATUS#@delimiter@"
            done  < <(\(diffCommand))
            """
        }
        
        let bracnhDiffCommand = "git diff --name-status \(isCIPipe ? "origin/" : "")\(targetBranch)...\(isCIPipe ? "origin/" : "")\(sourceBranch)"
        let stagedDiffCommand = "git diff --name-status --cached"
        
        switch diffSource {
        case .staged:
            let stagedStringDiff = try await commandExecutor.execute(
                сommandWithSingleOutput: gitDiffCommandBuilder(stagedDiffCommand),
                atPath: path
            )
            parseDiffWithNameOfFiles(
                output: stagedStringDiff
            ).forEach { filesChanges.insert($0) }
        case .branch:
            let branchStringDiff = try await commandExecutor.execute(
                сommandWithSingleOutput: gitDiffCommandBuilder(bracnhDiffCommand),
                atPath: path
            )
            parseDiffWithNameOfFiles(
                output: branchStringDiff
            ).forEach { filesChanges.insert($0) }
        case .combined:
            let stagedStringDiff = try await commandExecutor.execute(
                сommandWithSingleOutput: gitDiffCommandBuilder(stagedDiffCommand),
                atPath: path
            )
            let branchStringDiff = try await commandExecutor.execute(
                сommandWithSingleOutput: gitDiffCommandBuilder(bracnhDiffCommand),
                atPath: path
            )
            (parseDiffWithNameOfFiles(
                output: stagedStringDiff
            ) + parseDiffWithNameOfFiles(
                output: branchStringDiff
            )).forEach { filesChanges.insert($0) }
        }
    
        return Array(filesChanges)
    }
    
    func parseDiffWithNameOfFiles(
        output: String
    ) -> [FileChange] {
        let lines = output.split(separator: "@delimiter@")
        var fileChanges: [FileChange] = []
        for line in lines {
            let line = String(line)
            guard let status = line.slice(from: "#", to: "#"),
                  let fileName = line.slice(from: "%", to: "%")
            else { continue }
            switch status {
            case "A": // Add file
                fileChanges.append(
                    .added(
                        path: fileName
                    )
                )
            case "D": // Delete file
                fileChanges.append(
                    .delete(
                        path: fileName
                    )
                )
            case "M": // Modified file
                fileChanges.append(
                    .modified(
                        path: fileName
                    )
                )
            case let str where str.contains("R"): // Rename file
                let split = fileName.split(separator: "\t")
                fileChanges.append(
                    .renamed(
                        path: String(split[0]),
                        newPath: String(split[1]),
                        isModified: !status.contains("100")
                    )
                )
            default:
                logger.log(message: "Unknown status: \(status) for file: \(fileName)")
            }
        }
        return fileChanges
    }
    
    func parseDiffLineByLine(diff: String) -> [FileDiff] {
        let lines = diff.split(separator: "@delimiter@")
        var fileDiffs: [FileDiff] = []
        var currentOldFile: String?
        var currentNewFile: String?
        var currentChanges: [DiffLine] = []
        var originalLineNumber: Int?
        var newLineNumber: Int?
        for line in lines {
            if line.starts(with: "diff --git") {
                if let oldFile = currentOldFile, let newFile = currentNewFile {
                    let fileDiff = FileDiff(oldFilePath: oldFile, newFilePath: newFile, changes: currentChanges)
                    fileDiffs.append(fileDiff)
                }
                currentOldFile = extractOldFilePath(line: String(line))
                currentNewFile = extractNewFilePath(line: String(line))
                currentChanges = []
                originalLineNumber = nil
                newLineNumber = nil
            } else if line.starts(with: "@@") {
                let (oldStart, newStart) = parseHunkHeader(line: String(line))
                originalLineNumber = oldStart
                newLineNumber = newStart
                currentChanges.append(DiffLine(type: .context, content: String(line), lineNumberOriginal: nil, lineNumberNew: nil))
            } else if line.starts(with: "+") {
                currentChanges.append(DiffLine(type: .added, content: String(line), lineNumberOriginal: nil, lineNumberNew: newLineNumber))
                newLineNumber? += 1
            } else if line.starts(with: "-") {
                currentChanges.append(DiffLine(type: .removed, content: String(line), lineNumberOriginal: originalLineNumber, lineNumberNew: nil))
                originalLineNumber? += 1
            } else {
                currentChanges.append(DiffLine(type: .unchanged, content: String(line), lineNumberOriginal: originalLineNumber, lineNumberNew: newLineNumber))
                originalLineNumber? += 1
                newLineNumber? += 1
            }
        }
        if let oldFile = currentOldFile, let newFile = currentNewFile {
            let fileDiff = FileDiff(oldFilePath: oldFile, newFilePath: newFile, changes: currentChanges)
            fileDiffs.append(fileDiff)
        }
        return fileDiffs
    }
    
    private func extractOldFilePath(line: String) -> String {
        let components = line.components(separatedBy: " ")
        return components[1].trimmingCharacters(in: .whitespaces)
    }
    
    private func extractNewFilePath(line: String) -> String {
        let components = line.components(separatedBy: " ")
        return String(components[2].trimmingCharacters(in: .whitespaces).dropFirst(2))
    }
    
    private func parseHunkHeader(line: String) -> (Int, Int) {
        let rangePattern = #"@@ -(\d+),\d+ \+(\d+),\d+ @@"#
        let regex = try! NSRegularExpression(pattern: rangePattern)
        if let match = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.utf16.count)) {
            let oldStart = (line as NSString).substring(with: match.range(at: 1))
            let newStart = (line as NSString).substring(with: match.range(at: 2))
            return (Int(oldStart) ?? 0, Int(newStart) ?? 0)
        }
        return (0, 0)
    }
}

// MARK: - Subtypes

public extension CodeStylerService {
    
    struct ReceiverConfiguration {
        public init() {}
    }
    
    struct LocalConfiguration {
        let targetGitBranch: String
        let filesDiffCheckers: [any IFilesDiffChecker]
        let filesDiffSource: FilesDiffSource
        let excludeFilesWithNameContaints: [String]
        
        public init(targetGitBranch: String = "master", filesDiffCheckers: [any IFilesDiffChecker], filesDiffSource: FilesDiffSource, excludeFilesWithNameContaints: [String]) {
            self.targetGitBranch = targetGitBranch
            self.filesDiffCheckers = filesDiffCheckers
            self.filesDiffSource = filesDiffSource
            self.excludeFilesWithNameContaints = excludeFilesWithNameContaints
        }
    }
    
    struct GitlabConfiguration {
        let filesDiffCheckers: [any IFilesDiffChecker]
        let filesDiffSource: FilesDiffSource
        let excludeFilesWithNameContaints: [String]
        let mergeRequest: GitlabMergeRequest
        let mergeRequestCheckers: [any IGitlabMergeRequestChecker]
        
        public init(filesDiffCheckers: [any IFilesDiffChecker], filesDiffSource: FilesDiffSource, excludeFilesWithNameContaints: [String], mergeRequest: GitlabMergeRequest, mergeRequestCheckers: [any IGitlabMergeRequestChecker]) {
            self.filesDiffCheckers = filesDiffCheckers
            self.filesDiffSource = filesDiffSource
            self.excludeFilesWithNameContaints = excludeFilesWithNameContaints
            self.mergeRequest = mergeRequest
            self.mergeRequestCheckers = mergeRequestCheckers
        }
    }
    
    private final class ContinuationContainer {
        var continuation: CheckedContinuation<[any ICodeStylerMessage], any Error>?
        
        init(continuation: CheckedContinuation<[any ICodeStylerMessage], any Error>? = nil) {
            self.continuation = continuation
        }
    }
    
    private final class MessagesContainer {
        var messages: [any ICodeStylerMessage]
        init(messages: [any ICodeStylerMessage] = []) {
            self.messages = messages
        }
    }
    
    private final class ReceiveConnectionContainer {
        var port: CFMessagePort? = nil
        var runLoop: CFRunLoopSource? = nil
        
        init(port: CFMessagePort? = nil, runLoop: CFRunLoopSource? = nil) {
            self.port = port
            self.runLoop = runLoop
        }
    }

    enum FilesDiffSource: String, CaseIterable, Sendable {
        case staged
        case branch
        case combined
    }
    
    enum ServiceError: Error {
        /// Unable to determine the name of the current branch
        case notFindSourceBranch
        /// Error while receiving data via CFPort
        case cfPortReceiveDataError
        /// Not passed to GitLabService
        case not
        
        enum ReceiveError: LocalizedError {
            /// Задача была отменена
            case cancellationError
            
            var errorDescription: String? {
                switch self {
                case .cancellationError:
                    "Задача получения данных была отменена"
                }
            }
        }
    }
}
