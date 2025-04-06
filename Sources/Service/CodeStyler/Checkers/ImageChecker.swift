//
//  CheckJPGChecker.swift
//  RaifMagicCore
//
//  Created by USOV Vasily on 06.12.2024.
//

public final class ImageChecker: IFilesDiffChecker {
    
    private let source = CodeStylerMessageSource(title: "ImageChecker", description: "Правила по использованию графических файлов в проекте")
    
    public init() {}
    
    public func checkDiff(_ changedFiles: [FileChange], _ filesDiff: [FileDiff]) async throws -> [any ICodeStylerMessage] {
        changedFiles
            .compactMap {
                switch $0 {
                case .added(path: let path): mapToErrorIfNeeded(path: path)
                case .modified(path: let path): mapToErrorIfNeeded(path: path)
                case .renamed(path: _, newPath: let path, isModified: _): mapToErrorIfNeeded(path: path)
                default: nil
                }
            }
    }
    
    private func mapToErrorIfNeeded(path: String) -> FileErrorMessage? {
        guard path.hasSuffix(".jpg") || path.hasSuffix(".jpeg") else {
            return nil
        }
        return FileErrorMessage(filePath: path,
                         message: "Вместо JPG стоит попробовать файл другого формата",
                         source: source,
                         level: .warning)
    }
}
