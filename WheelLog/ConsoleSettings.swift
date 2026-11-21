import SwiftUI
import UniformTypeIdentifiers

struct GarageView: View {
    @ObservedObject var wheel: WheelConnection
    @ObservedObject var store: ConsoleStore
    let openSettings: () -> Void
    let openDashboard: () -> Void

    var body: some View {
        RideScreen(title: "Гараж") {
            RidePanel {
                Text(wheel.status).font(.subheadline).foregroundStyle(RideColors.muted)
                if wheel.connectedID != nil {
                    Button("Управление колесом", systemImage: "switch.2", action: openSettings)
                        .buttonStyle(.borderedProminent)
                    Button("Отключиться", systemImage: "bolt.slash") { wheel.disconnect() }
                        .buttonStyle(.bordered)
                } else {
                    if wheel.state == .scanning {
                        Button("Остановить поиск", systemImage: "stop.circle") { wheel.stopScan() }
                            .buttonStyle(.bordered)
                    } else {
                        Button("Найти колесо", systemImage: "antenna.radiowaves.left.and.right") { wheel.scan() }
                            .buttonStyle(.borderedProminent)
                    }
                    Picker("Протокол для поиска", selection: $wheel.preferredFamily) {
                        ForEach(WheelFamily.allCases) { Text($0.title).tag($0) }
                    }
                    .disabled(wheel.state == .scanning)
                }
            }
            if !store.settings.wheels.isEmpty {
                Text("Мои колёса").font(.headline)
                ForEach(store.settings.wheels) { entry in
                    RidePanel {
                        Button {
                            if wheel.connectedID == entry.id { openDashboard() }
                            else {
                                wheel.preferredFamily = WheelFamily(rawValue: entry.protocolKey) ?? .automatic
                                wheel.scan(for: entry.id)
                            }
                        } label: {
                            entryLabel(name: entry.name, detail: entry.model, icon: "circle.circle")
                        }
                        .buttonStyle(.plain)
                        .disabled(wheel.connectedID != nil && wheel.connectedID != entry.id)
                    }
                }
            }
            let nearby = wheel.devices.filter { device in
                !store.settings.wheels.contains(where: { $0.id == device.id })
            }
            if wheel.connectedID == nil, !nearby.isEmpty {
                Text("Рядом").font(.headline)
                ForEach(nearby) { device in
                    RidePanel {
                        Button { wheel.connect(device) } label: {
                            entryLabel(name: device.name,
                                       detail: "\(device.hint?.title ?? "BLE") · \(device.rssi) дБм",
                                       icon: "dot.radiowaves.left.and.right")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Button(wheel.demo ? "Выключить демонстрацию" : "Открыть демонстрацию", systemImage: "play.circle") {
                wheel.setDemo(!wheel.demo)
                if wheel.demo { openDashboard() }
            }
            .disabled(wheel.connectedID != nil)
        }
    }

    private func entryLabel(name: String, detail: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(RideColors.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.headline)
                Text(detail).foregroundStyle(RideColors.muted).font(.caption)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption)
        }
        .contentShape(Rectangle())
    }
}

struct BoardSettings: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ConsoleStore
    let profile: String
    @State private var draft: ConsoleBoard
    @State private var importing = false
    @State private var exporting = false
    @State private var deleting = false
    @State private var fileError: String?

    init(store: ConsoleStore, profile: String, board: ConsoleBoard) {
        self.store = store
        self.profile = profile
        _draft = State(initialValue: board)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Панель") {
                    TextField("Название", text: $draft.title)
                    Picker("Показатель вверху", selection: $draft.pinned) {
                        Text("Скрыт").tag(ConsoleMetric?.none)
                        ForEach(ConsoleMetric.allCases) { Text($0.title).tag(Optional($0)) }
                    }
                }
                if !draft.tiles.isEmpty {
                    Section("Порядок плиток") {
                        ForEach(draft.tiles) { tile in
                            VStack(alignment: .leading) {
                                Label(tile.style.title, systemImage: tile.style.icon)
                                Text(tile.metrics.map(\.title).joined(separator: ", "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .onMove { indices, position in draft.tiles.move(fromOffsets: indices, toOffset: position) }
                        .onDelete { draft.tiles.remove(atOffsets: $0) }
                    }
                }
                Section("Файл раскладки") {
                    Button("Экспорт JSON", systemImage: "square.and.arrow.up") { exporting = true }
                        .disabled(title.isEmpty)
                    Button("Импорт новой панели", systemImage: "square.and.arrow.down") { importing = true }
                }
                if store.boards(for: profile).count > 1 {
                    Section { Button("Удалить панель", role: .destructive) { deleting = true } }
                }
            }
            .navigationTitle("Панель приборов")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if draft.tiles.count > 1 { EditButton() }
                    Button("Готово") { store.update(exportBoard, profile: profile); dismiss() }.disabled(title.isEmpty)
                }
            }
            .confirmationDialog("Удалить панель «\(draft.title)»?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Удалить панель", role: .destructive) { store.deleteBoard(draft, profile: profile); dismiss() }
            }
            .fileExporter(isPresented: $exporting, document: BoardFile(board: exportBoard),
                          contentType: .json, defaultFilename: "RideConsole") { result in
                if case .failure = result { fileError = "Не удалось сохранить раскладку." }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json], onCompletion: importBoard)
            .alert("Файл раскладки", isPresented: Binding(
                get: { fileError != nil }, set: { if !$0 { fileError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(fileError ?? "")
            }
        }
    }

    private var title: String { String(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(48)) }

    private var exportBoard: ConsoleBoard {
        var board = draft
        board.title = title
        return board
    }

    private func importBoard(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard (1...524_288).contains(size) else { throw CocoaError(.fileReadCorruptFile) }
            let board = try BoardFile.decode(Data(contentsOf: url))
            store.addBoard(board, profile: profile)
            dismiss()
        } catch {
            fileError = "Не удалось прочитать раскладку Ride Console."
        }
    }
}

struct ConsoleSettings: View {
    @ObservedObject var store: ConsoleStore
    @ObservedObject var wheel: WheelConnection
    @ObservedObject var library: RideLibrary
    let events: [RideEvent]
    @AppStorage("keepDashboardAwake") private var keepDashboardAwake = true
    @State private var editingAlert: ConsoleAlert?
    @State private var showEvents = false

    var body: some View {
        RideScreen(title: "Настройки") {
            RidePanel {
                Toggle("Держать экран приборов включённым", isOn: $keepDashboardAwake)
                Toggle("Подключать последнее колесо", isOn: $store.settings.autoConnect)
                Toggle("Начинать GPS-запись при подключении", isOn: $store.settings.automaticRide)
                Button(library.logging ? "Завершить CSV" : "Записать CSV", systemImage: "doc.text") {
                    if library.logging { library.stopLog() }
                    else { library.startLog(source: wheel.sourceKey) }
                }
                .disabled(!library.logging && wheel.state != .live && !wheel.demo)
                Button("Сбросить максимумы", systemImage: "arrow.counterclockwise") { wheel.resetExtrema() }
            }
            RidePanel {
                Text("Оповещения").font(.headline)
                ForEach(store.settings.rules) { rule in
                    Button {
                        editingAlert = rule
                    } label: {
                        Label(rule.name, systemImage: rule.enabled ? "bell" : "bell.slash")
                    }
                }
                Button("Добавить оповещение", systemImage: "plus") { editingAlert = ConsoleAlert() }
            }
            RidePanel {
                Button("Журнал событий", systemImage: "list.bullet") { showEvents = true }
                if let message = store.errorMessage { Text(message).foregroundStyle(.red) }
            }
        }
        .sheet(item: $editingAlert) { rule in
            AlertEditor(rule: rule, existing: store.settings.rules.contains(where: { $0.id == rule.id })) { updated in
                if let index = store.settings.rules.firstIndex(where: { $0.id == rule.id }) {
                    if let updated { store.settings.rules[index] = updated }
                    else { store.settings.rules.remove(at: index) }
                } else if let updated {
                    store.settings.rules.append(updated)
                }
            }
        }
        .sheet(isPresented: $showEvents) {
            RideScreen(title: "Журнал событий", showsClose: true) {
                if events.isEmpty { Text("Событий пока нет.").foregroundStyle(RideColors.muted) }
                ForEach(events) { event in
                    RidePanel {
                        Text(event.date, style: .time).font(.caption.monospacedDigit()).foregroundStyle(RideColors.muted)
                        Text(event.message).font(.subheadline)
                    }
                }
            }
        }
    }
}

private struct AlertEditor: View {
    let existing: Bool
    let save: (ConsoleAlert?) -> Void
    @State private var rule: ConsoleAlert
    @Environment(\.dismiss) private var dismiss

    init(rule: ConsoleAlert, existing: Bool, save: @escaping (ConsoleAlert?) -> Void) {
        _rule = State(initialValue: rule)
        self.existing = existing
        self.save = save
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Оповещение") {
                    TextField("Название", text: $rule.name)
                    Toggle("Включено", isOn: $rule.enabled)
                    Picker("Сигнал", selection: $rule.signal) {
                        ForEach(ConsoleAlert.Signal.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Stepper("Задержка: \(Int(rule.hold)) с", value: $rule.hold, in: 0...60)
                    Stepper(rule.repeatEvery == 0 ? "Повтор выключен" : "Повтор: \(Int(rule.repeatEvery)) с",
                            value: $rule.repeatEvery, in: 0...120, step: 5)
                }
                Section("Условия") {
                    Picker("Должны выполниться", selection: $rule.requireAll) {
                        Text("Все").tag(true)
                        Text("Любое").tag(false)
                    }
                    ForEach($rule.conditions) { $condition in
                        VStack(alignment: .leading) {
                            Picker("Метрика", selection: $condition.metric) {
                                ForEach(ConsoleMetric.allCases) { Text($0.title).tag($0) }
                            }
                            Picker("Порог", selection: $condition.comparison) {
                                ForEach(AlertCondition.Comparison.allCases) { Text($0.rawValue).tag($0) }
                            }
                            HStack {
                                TextField("Значение", value: $condition.threshold, format: .number)
                                    .keyboardType(.numbersAndPunctuation)
                                Text(condition.metric.unit).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { rule.conditions.remove(atOffsets: $0) }
                    Button("Добавить условие", systemImage: "plus") { rule.conditions.append(AlertCondition()) }
                        .disabled(rule.conditions.count >= 8)
                }
                if existing {
                    Section { Button("Удалить оповещение", role: .destructive) { save(nil); dismiss() } }
                }
            }
            .navigationTitle("Порог телеметрии")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        rule.name = String(rule.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(72))
                        save(rule)
                        dismiss()
                    }
                    .disabled(rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              rule.conditions.isEmpty || rule.conditions.contains(where: { !$0.threshold.isFinite }))
                }
            }
        }
    }
}
