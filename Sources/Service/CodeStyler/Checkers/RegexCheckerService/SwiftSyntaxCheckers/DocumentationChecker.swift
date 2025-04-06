//
//  DocumentationChecker.swift
//  RaifMagicCore
//
//  Created by ANPILOV Roman on 19.11.2024.
//

import SwiftSyntax

/// Проверка файла на содержание документации у публичных функций/протоколов
final class DocumentationChecker: SyntaxVisitor {
    var source: String = ""
    var messages: [(String, Int)] = []

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.modifiers.contains(where: { $0.name.text == "public" }) else {
            return .skipChildren
        }
        
        if !hasDocumentation(node.leadingTrivia) {
            let (line, _) = node.positionAfterSkippingLeadingTrivia.lineAndColumn(
                lines: source.components(separatedBy: .newlines)
            )
            messages.append(("У публичного протокола \"\(node.name.text)\" отсутствует документация", line))
        }
        
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        var currentParent = node.parent
        while let parent = currentParent {
            if let protocolDecl = parent.as(ProtocolDeclSyntax.self),
               protocolDecl.modifiers.contains(where: { $0.name.text == "public" }) {
                
                if !hasDocumentation(node.leadingTrivia) {
                    let (line, _) = node.positionAfterSkippingLeadingTrivia.lineAndColumn(
                        lines: source.components(separatedBy: .newlines)
                    )
                    messages.append(("У публичной функции \"\(node.name.text)\" внутри публичного протокола отсутствует документация", line))
                }
                
                for param in node.signature.parameterClause.parameters {
                    print(param)
                    if !hasParameterDocumentation(node.leadingTrivia, parameter: param.firstName.text) {
                        let (line, _) = param.positionAfterSkippingLeadingTrivia.lineAndColumn(
                            lines: source.components(separatedBy: .newlines)
                        )
                        messages.append(("У параметра \"\(param.firstName.text)\" в публичной функции \"\(node.name.text)\" отсутствует документация", line))
                    }
                }
                
                break
            }
            currentParent = parent.parent
        }
        
        return .skipChildren
    }
    
    private func hasDocumentation(_ trivia: Trivia?) -> Bool {
        guard let trivia = trivia else { return false }
        for piece in trivia {
            switch piece {
            case .docLineComment(_), .docBlockComment(_):
                return true
            default:
                continue
            }
        }
        return false
    }
    
    private func hasParameterDocumentation(_ trivia: Trivia?, parameter: String) -> Bool {
        guard let trivia = trivia else { return false }
        for piece in trivia {
            switch piece {
            case let .docLineComment(comment), let .docBlockComment(comment):
                if comment.contains(parameter) {
                    return true
                }
            default:
                continue
            }
        }
        return false
    }
}
