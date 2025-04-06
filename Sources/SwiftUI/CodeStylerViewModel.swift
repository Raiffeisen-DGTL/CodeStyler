//
//  CodeStylerViewModel.swift
//  RaifMagic
//
//  Created by ANPILOV Roman on 25.10.2024.
//

import AppKit
import Foundation
import Observation
import CommandExecutor
import CodeStyler

@Observable
@MainActor
public final class CodeStylerViewModel {
    let commandExecutor: CommandExecutor
    let logger: ICodeStylerLogger
    let service: CodeStylerService
    let projectPath: String
    
    let targetGitBranch: String
    let filesDiffCheckers: [any IFilesDiffChecker]
    let excludeFilesWithNameContaints: [String]
    
    public init(commandExecutor: CommandExecutor,
                logger: ICodeStylerLogger,
                projectPath: String,
                targetGitBranch: String,
                filesDiffCheckers: [any IFilesDiffChecker],
                excludeFilesWithNameContaints: [String]) {
        self.commandExecutor = commandExecutor
        self.logger = logger
        self.projectPath = projectPath
        self.targetGitBranch = targetGitBranch
        self.filesDiffCheckers = filesDiffCheckers
        self.excludeFilesWithNameContaints = excludeFilesWithNameContaints
        self.service = CodeStylerService(commandExecutor: commandExecutor, logger: logger)
    }
    
    var responseMessages: [any ICodeStylerMessage] = [] {
        didSet {
            // разбираем сообщения по файлам
            // паралельно собираем данных о типах источников
            
            messagesSources = []
            
            let uniquePaths = responseMessages.compactMap { message -> String? in
                if let fileMessage = message as? FileErrorMessage {
                    fileMessage.filePath
                } else if let codeStyleMessage = message as? CodeStyleErrorMessage {
                    codeStyleMessage.filePath
                } else {
                    nil
                }
            }
            
            filesWithErrors = Array(Set(uniquePaths)).map { filePath in
                let messages =  responseMessages.compactMap { message -> DisplayableMessage? in
                    if messagesSources.firstIndex(where: { item in
                        item.wrapped == message.source
                    }) == nil {
                        messagesSources.append(DisplayableMessageSource(wrapped: message.source, isShowing: true))
                    }
                    return if let fileMessage = message as? FileErrorMessage, fileMessage.filePath == filePath {
                        DisplayableMessage(id: fileMessage.id,
                                                    message: fileMessage.message,
                                                    source: fileMessage.source,
                                                    level: fileMessage.level)
                    } else if let codeStyleMessage = message as? CodeStyleErrorMessage, codeStyleMessage.filePath == filePath {
                        DisplayableMessage(id: codeStyleMessage.id,
                                                    message: codeStyleMessage.message,
                                                    source: codeStyleMessage.source,
                                                    level: codeStyleMessage.level,
                                                    action: .openFileLine(filePath: codeStyleMessage.filePath, line: codeStyleMessage.line))
                    } else { nil }
                }.sorted(by: {$0.source.title < $1.source.title })
                return DisplayableFile(filePath: filePath,
                                       messages: messages)
            }.sorted(by: {$0.filePath < $1.filePath })
        }
    }
    // наполняется автоматически при изменении массива полученных сообщений
    private(set) var filesWithErrors: [DisplayableFile] = []
    var messagesSources: [DisplayableMessageSource] = []
    
    var isInitial: Bool = true
    
    func runCodeStyler(diffSource: CodeStylerService.FilesDiffSource) async throws {
        isInitial = false

        // If you want to use CodeStyler directly, then use the following code. In this case, the diff analysis will be called directly
        let configuration = CodeStylerService.LocalConfiguration(
            filesDiffCheckers: filesDiffCheckers,
            filesDiffSource: diffSource,
            excludeFilesWithNameContaints: excludeFilesWithNameContaints)
        responseMessages = try await service.analyze(localConfiguration: configuration, projectPath: projectPath)
        
        // if the code styler is used in another application (for example in CLI) and you want to get data from it, then use the code below
//        let portID = String(Int.random(in: 1000...100000))
//        let command = Command("magic code-styler \(projectPath) --diff-source \(diffSource.rawValue) --run-raif-magic false --port-id \(portID)")
//        async let _ = try await commandExecutor.execute(command)
//        try await Task.sleep(for: .seconds(1))
//        responseMessages = try await service.receiveMessagesFromCFPort(portID: portID)
    }
    
    private func startReceivingMessages() async throws {
        responseMessages = []
        responseMessages = try await service.receiveMessagesFromCFPort(portID: projectPath)
    }
    
    func showFileInFinder(projectPath: String, file: DisplayableFile) {
        let files = [URL(fileURLWithPath: "\(projectPath)/\(file.filePath)")]
        NSWorkspace.shared.activateFileViewerSelecting(files)
    }
    
    func openFile(filePath: String, lineNumber: String?) async throws {
        let textForCommand = "xed -l \(lineNumber ?? "0") \(filePath)"
        try await commandExecutor.execute(
            textCommand: textForCommand
        )
    }
}
