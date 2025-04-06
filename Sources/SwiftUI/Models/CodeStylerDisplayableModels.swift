//
//  Untitled.swift
//  RaifMagic
//
//  Created by USOV Vasily on 10.12.2024.
//

import CodeStyler

/// Model for displaying files with errors in UI styler code
struct DisplayableFile: Identifiable {
    var id: Int {
        filePath.hashValue
    }
    let filePath: String
    let messages: [DisplayableMessage]
}

/// Model for displaying errors inside a file in the UI styler code
struct DisplayableMessage: Identifiable {
    let id: Int
    let message: String
    let source: CodeStylerMessageSource
    let level: CodeStyleMessageLevel
    let action: Action?
    
    init(id: Int, message: String, source: CodeStylerMessageSource, level: CodeStyleMessageLevel, action: Action? = nil) {
        self.id = id
        self.message = message
        self.source = source
        self.level = level
        self.action = action
    }
    
    enum Action {
        case openFileLine(filePath: String, line: String)
    }
}

/// Model for displaying error source inside styler code for filtering messages
struct DisplayableMessageSource: Identifiable {
    var id: Int {
        wrapped.title.hashValue
    }
    let wrapped: CodeStylerMessageSource
    var isShowing: Bool
}
