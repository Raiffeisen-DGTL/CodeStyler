//
//  LinterModels.swift
//  
//
//  Created by ANPILOV Roman on 18.09.2024.
//

import Foundation

/// Протокол моделек линтера проекта
public protocol ICodeStylerMessage: Sendable, Identifiable, Hashable, Codable {
    var id: Int { get }
    var message: String { get }
    var source: CodeStylerMessageSource { get }
    var level: CodeStyleMessageLevel { get }
}

/// Обертка над моделями линтера, чтобы поддержать Identifable & Equatable где требуется any ICodeStylerMessage
public struct AnyWrappedStyleMessage: Identifiable, Equatable, Sendable {
    public static func == (
        lhs: AnyWrappedStyleMessage,
        rhs: AnyWrappedStyleMessage
    ) -> Bool {
        if let lhs = lhs.message as? FileErrorMessage, let rhs = rhs.message as? FileErrorMessage {
            lhs == rhs
        } else if let lhs = lhs.message as? CodeStyleErrorMessage, let rhs = rhs.message as? CodeStyleErrorMessage {
            lhs == rhs
        } else { false }
    }
    
    public var message: any ICodeStylerMessage
    public var id: Int {
        message.id
    }
    
    public init(message: any ICodeStylerMessage) {
        self.message = message
    }
}

/// Источник ошибки код-стайлера
public struct CodeStylerMessageSource: Codable, Sendable, Equatable, Hashable {
    public var title: String
    public var description: String
}

/// Тип ошибки код-стайлера
public enum CodeStyleMessageLevel: String, Codable, Sendable, Equatable, Hashable {
    case error
    case warning
}

// MARK: - Messages Implementations

/// Модель, представляющая ошибку мердж реквеста
public struct MergeRequestErrorMessage: ICodeStylerMessage {
    public var id: Int {
        message.hashValue
    }
    public let message: String
    public let source: CodeStylerMessageSource
    public let level: CodeStyleMessageLevel
}

/// Модель, представляющяя ошибку по конкретному файлу целиком
public struct FileErrorMessage: ICodeStylerMessage {
    public let id: Int
    public let filePath: String
    public let message: String
    public let source: CodeStylerMessageSource
    public let level: CodeStyleMessageLevel
    
    init(filePath: String, message: String, source: CodeStylerMessageSource, level: CodeStyleMessageLevel) {
        self.filePath = filePath
        self.message = message
        self.id = (message + filePath).hashValue
        self.level = level
        self.source = source
    }
}

/// Модель, представляющяя ошибку по конкретной строчке кода в файле
public struct CodeStyleErrorMessage: ICodeStylerMessage {
    public let id: Int
    public let message: String
    public let source: CodeStylerMessageSource
    public let level: CodeStyleMessageLevel
    public let typeOfChange: DiffLineType
    public let line: String
    public let filePath: String
    
    init(message: String, typeOfChange: DiffLineType, line: String, filePath: String, source: CodeStylerMessageSource, level: CodeStyleMessageLevel) {
        self.message = message
        self.typeOfChange = typeOfChange
        self.line = line
        self.filePath = filePath
        self.id = (message + line + filePath).hashValue
        self.level = level
        self.source = source
    }
}

/// Модель для передачи по CFPort
public struct CodeStyleMessageDTO: Codable {
    public let base: MessageType
    
    public enum MessageType: Codable {
        case file(FileErrorMessage)
        case code(CodeStyleErrorMessage)
    }
}
