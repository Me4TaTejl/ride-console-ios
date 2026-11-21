import AVFoundation
import AudioToolbox
import SwiftUI
import UniformTypeIdentifiers
import UIKit

@MainActor
final class ConsoleStore: ObservableObject {
    struct Settings: Codable {
        var wheels = [GarageEntry]()
        var boards = [String: [ConsoleBoard]]()
        var activeBoards = [String: UUID]()
        var rules = [ConsoleAlert]()
        var autoConnect = true
        var automaticRide = false
        var lastWheel: UUID?
    }

    @Published var settings: Settings { didSet { save() } }
    @Published private(set) var errorMessage: String?
    private let defaults: UserDefaults
    private let key = "consoleProfile.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key) {
            do { settings = try JSONDecoder().decode(Settings.self, from: data) }
            catch {
                settings = Settings()
                errorMessage = "Сохранённые настройки не удалось прочитать."
            }
        } else {
            settings = Settings()
        }
    }

    func profile(id: UUID?, demo: Bool) -> String {
        if demo { return "demo" }
        return (id ?? settings.lastWheel)?.uuidString ?? "default"
    }

    func boards(for profile: String) -> [ConsoleBoard] {
        settings.boards[profile].flatMap { $0.isEmpty ? nil : $0 } ?? []
    }

    func setupBoard(for profile: String) {
        if boards(for: profile).isEmpty { addBoard(.standard, profile: profile) }
    }

    func board(for profile: String) -> ConsoleBoard? {
        let items = boards(for: profile)
        return items.first(where: { $0.id == settings.activeBoards[profile] }) ?? items.first
    }

    func addBoard(_ board: ConsoleBoard, profile: String) {
        var next = settings
        next.boards[profile, default: []].append(board)
        next.activeBoards[profile] = board.id
        settings = next
    }

    func update(_ board: ConsoleBoard, profile: String) {
        guard let index = settings.boards[profile]?.firstIndex(where: { $0.id == board.id }) else { return }
        settings.boards[profile]?[index] = board
    }

    func deleteBoard(_ board: ConsoleBoard, profile: String) {
        guard boards(for: profile).count > 1 else { return }
        settings.boards[profile]?.removeAll { $0.id == board.id }
    }

    func seenWheel(_ entry: GarageEntry) {
        var next = settings
        if let index = next.wheels.firstIndex(where: { $0.id == entry.id }) {
            next.wheels[index].model = entry.model
            next.wheels[index].protocolKey = entry.protocolKey
        } else {
            next.wheels.append(entry)
        }
        next.lastWheel = entry.id
        settings = next
    }

    private func save() {
        do {
            defaults.set(try JSONEncoder().encode(settings), forKey: key)
        } catch {
            errorMessage = "Не удалось сохранить настройки."
        }
    }
}

struct BoardFile: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    let board: ConsoleBoard

    init(board: ConsoleBoard) { self.board = board }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        board = try Self.decode(data)
    }

    static func decode(_ data: Data) throws -> ConsoleBoard {
        var board = try JSONDecoder().decode(ConsoleBoard.self, from: data)
        guard board.tiles.count <= 48, !board.title.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        board.id = UUID()
        board.title = String(board.title.prefix(48))
        for index in board.tiles.indices {
            board.tiles[index].id = UUID()
            let metrics = board.tiles[index].metrics
            guard !metrics.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            board.tiles[index].setMetrics(metrics)
        }
        return board
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(board))
    }
}

@MainActor
final class ConsoleSamples: ObservableObject {
    @Published private(set) var series = [ConsoleMetric: [Double?]]()
    @Published private(set) var lastAlert: String?
    private var lastTime: TimeInterval = -.infinity
    private var engine = ConsoleRuleEngine()
    private let speaker = AVSpeechSynthesizer()

    func reset() {
        series.removeAll()
        lastTime = -.infinity
        clearAlerts()
    }

    func clearAlerts() {
        engine.stop()
        speaker.stopSpeaking(at: .immediate)
        lastAlert = nil
    }

    func receive(_ values: [ConsoleMetric: Double], rules: [ConsoleAlert], live: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastTime >= 0.16 else { return }
        lastTime = now
        var next = series
        for metric in ConsoleMetric.allCases {
            next[metric, default: []].append(values[metric])
            if let count = next[metric]?.count, count > 180 {
                next[metric]?.removeFirst(count - 180)
            }
        }
        series = next
        guard live else { return }
        for rule in engine.evaluate(rules, at: now, readings: values) {
            lastAlert = rule.name
            switch rule.signal {
            case .sound: AudioServicesPlaySystemSound(1103)
            case .vibration: AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            case .voice:
                guard !speaker.isSpeaking else { continue }
                let message = AVSpeechUtterance(string: rule.name)
                message.voice = AVSpeechSynthesisVoice(language: "ru-RU")
                speaker.speak(message)
            }
        }
    }
}
