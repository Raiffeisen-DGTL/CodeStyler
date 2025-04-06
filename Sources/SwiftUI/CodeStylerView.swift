//
//  CodeStylerView.swift
//  RaifMagic
//
//  Created by ANPILOV Roman on 25.10.2024.
//

import SwiftUI
import CodeStyler
import CommandExecutor
import MagicDesign

public struct CodeStylerView: View {
    private var initialOpenCFPortReceiverWithPortID: String?
    
    @State private var codeStylerViewModel: CodeStylerViewModel
    @State private var receivingTask: Task<Void, Never>? = nil
    
    @AppStorage("selectedDiff") private var selectedDiffSource: CodeStylerService.FilesDiffSource = .combined
    
    public init(projectPath: String,
                openCFPortReceiverWithPortID: String?,
                targetGitBranch: String,
                filesDiffCheckers: [any IFilesDiffChecker],
                excludeFilesWithNameContaints: [String],
                commandExecutor: CommandExecutor,
                logger: ICodeStylerLogger) {
        self.initialOpenCFPortReceiverWithPortID = openCFPortReceiverWithPortID
        var correctProjectPath = {
            if let last = projectPath.last, last == "/" {
                projectPath
            } else {
                projectPath + "/"
            }
        }()
        _codeStylerViewModel = State(wrappedValue: CodeStylerViewModel(commandExecutor: commandExecutor,
                                                                       logger: logger,
                                                                       projectPath: correctProjectPath,
                                                                       targetGitBranch: targetGitBranch,
                                                                       filesDiffCheckers: filesDiffCheckers,
                                                                       excludeFilesWithNameContaints: excludeFilesWithNameContaints))
    }
    
    public var body: some View {
        HStack(spacing: 0) {
            Form {
                if codeStylerViewModel.isInitial {
                    if initialOpenCFPortReceiverWithPortID == nil {
                        Text("Для поиска и отображения ошибок запустите поиск")
                    } else {
                        ProgressView()
                    }
                } else if receivingTask != nil {
                    ProgressView()
                } else {
                    let usingSources = codeStylerViewModel.messagesSources.filter { $0.isShowing }.map(\.wrapped)
                    if usingSources.isEmpty {
                        Text("Ошибок нет")
                    } else {
                        ForEach(codeStylerViewModel.filesWithErrors) { file in
                            let messages = file.messages.filter { usingSources.contains($0.source) }
                            if messages.isEmpty == false {
                                Section(content:  {
                                    Table(messages) {
                                        TableColumn("Описание") { item in
                                            HStack(spacing: 10) {
                                                switch item.level {
                                                case .error:
                                                    Circle()
                                                        .fill(Color.red)
                                                        .frame(width: 8, height: 8)
                                                case .warning:
                                                    Circle()
                                                        .fill(Color.yellow)
                                                        .frame(width: 8, height: 8)
                                                }
                                                Text(item.message)
                                                    .lineLimit(4)
                                            }
                                        }
                                        TableColumn("Источник") { item in
                                            Text(item.source.title)
                                        }
                                        .width(150)
                                        TableColumn("Действие") { item in
                                            if case .openFileLine(let path, let line) = item.action {
                                                Button {
                                                    Task {
                                                        try await codeStylerViewModel.openFile(
                                                            filePath: "\(codeStylerViewModel.projectPath)/\(path)",
                                                            lineNumber: line
                                                        )
                                                    }
                                                } label: {
                                                    Text("Открыть")
                                                }
                                                .buttonStyle(.bordered)
                                            }
                                        }
                                        .width(100)
                                        .alignment(.center)
                                    }
                                }, header: {
                                    HStack {
                                        Text(file.filePath)
                                            .font(.title3)
                                        Spacer()
                                        Button { codeStylerViewModel.showFileInFinder(projectPath: codeStylerViewModel.projectPath, file: file) } label: {
                                            Text("Показать в Finder")
                                        }
                                    }
                                })
                            }
                        }
                    }
                }
            }
            AppSidebar {
                Section("Поиск ошибок") {
                    VStack(alignment: .trailing) {
                        Picker(selection: $selectedDiffSource, label: Text("Анализировать")) {
                            ForEach(CodeStylerService.FilesDiffSource.allCases, id: \.self) { source in
                                Text(diffSourceSelectorDescription(source))
                            }
                        }
                        Button {
                            receivingTask?.cancel()
                            receivingTask = Task {
                                do {
                                    try await codeStylerViewModel.runCodeStyler(diffSource: selectedDiffSource)
                                    receivingTask = nil
                                } catch {
                                    print(error)
                                }
                            }
                        } label: {
                            Text("Запустить поиск")
                        }
                        .disabled(
                            receivingTask != nil
                        )
                    }
                }
                if codeStylerViewModel.responseMessages.isEmpty == false {
                    Section("Операции") {
                        VStack(alignment: .leading) {
                            let hasSwiftformatErrors = codeStylerViewModel.responseMessages.contains(where: { $0.source.title.lowercased() == "swiftformat" })
                            SidebarCustomOperationView(operation: .init(title: "Запустить SwiftFormat по диффу", description: "Запуск возможен при наличии найденных ошибок от SwiftFormat", icon: "play", confirmationDescription: "Запуск может привести к изменению исходного кода", closure: {
                                if hasSwiftformatErrors {
                                    Task { @MainActor in
                                        var scenario = CommandScenario(title: "Форматирование SwiftFormat по диффу из CodeStyler")
                                        let sfFiles = await codeStylerViewModel.filesWithErrors.compactMap {
                                            if $0.messages.contains(where: { $0.source.title.lowercased() == "swiftformat" }) { $0 }
                                            else { nil }
                                        }
                                        for file in sfFiles {
                                            let command = Command("swiftformat \(codeStylerViewModel.projectPath)\(file.filePath)")
                                            try? await codeStylerViewModel.commandExecutor.execute(command)
                                        }
                                        codeStylerViewModel.responseMessages = await codeStylerViewModel.responseMessages.filter({ $0.source.title.lowercased() != "swiftformat" })
                                    }
                                }
                            }))
                            .disabled(
                                hasSwiftformatErrors == false
                            )
                        }
                    }
                }
                if codeStylerViewModel.messagesSources.isEmpty == false {
                    Section("Фильтр ошибок") {
                        ForEach(Bindable(codeStylerViewModel).messagesSources) { source in
                            Toggle(isOn: source.isShowing) {
                                Text(source.wrappedValue.wrapped.title)
                                Text(source.wrappedValue.wrapped.description)
                                    .font(.footnote)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .formStyle(.grouped)
        .task {
            codeStylerViewModel.logger.log(message: "Открытие экрана код-стайлера")
            do {
                if let initialOpenCFPortReceiverWithPortID {
                    codeStylerViewModel.logger.log(message: "Автоматическое открытие получения данных через порт с id \(initialOpenCFPortReceiverWithPortID)")
                    codeStylerViewModel.responseMessages = try await codeStylerViewModel.service.receiveMessagesFromCFPort(portID: initialOpenCFPortReceiverWithPortID)
                    codeStylerViewModel.isInitial = false
                }
            } catch {
                codeStylerViewModel.logger.log(error: "Error during receiving messages from port. Error is \(error)")
            }
        }
        .onDisappear {
            receivingTask?.cancel()
        }
        .task {
            
        }
    }
    
    private func diffSourceSelectorDescription(_ source: CodeStylerService.FilesDiffSource) -> String {
        switch source {
        case .staged: "Стейдж"
        case .branch: "Коммиты текущей ветки"
        case .combined: "Стейдж + Коммиты"
        }
    }
    
    private func diffSourceDescription(_ source: CodeStylerService.FilesDiffSource) -> String {
        switch source {
        case .staged: "Стейдже"
        case .branch: "Коммитах текущей ветки"
        case .combined: "Стейдже + Коммитах текущей ветки"
        }
    }
}
