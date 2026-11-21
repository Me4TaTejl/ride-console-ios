import Foundation

enum ConsoleMetric: String, Codable, CaseIterable, Identifiable {
    case wheelSpeed, gpsSpeed, pwm, battery, controller, motor, voltage, power, current, phaseCurrent
    case trip, odometer, altitude, ascent

    var id: Self { self }

    var title: String {
        switch self {
        case .wheelSpeed: "Скорость колеса"
        case .gpsSpeed: "Скорость GPS"
        case .pwm: "PWM"
        case .battery: "Заряд"
        case .controller: "Температура контроллера"
        case .motor: "Температура мотора"
        case .voltage: "Напряжение"
        case .power: "Мощность"
        case .current: "Ток батареи"
        case .phaseCurrent: "Фазный ток"
        case .trip: "Пробег поездки"
        case .odometer: "Общий пробег"
        case .altitude: "Высота"
        case .ascent: "Набор высоты"
        }
    }

    var unit: String {
        switch self {
        case .wheelSpeed, .gpsSpeed: "км/ч"
        case .pwm, .battery: "%"
        case .controller, .motor: "°C"
        case .voltage: "В"
        case .power: "Вт"
        case .current, .phaseCurrent: "А"
        case .trip, .odometer: "км"
        case .altitude, .ascent: "м"
        }
    }

    func reading(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        let decimals: Int = switch self {
        case .battery, .power, .odometer, .altitude, .ascent: 0
        case .trip: 2
        default: 1
        }
        return value.formatted(.number.grouping(.never).precision(.fractionLength(decimals)))
    }

    var maximum: Double {
        switch self {
        case .wheelSpeed, .gpsSpeed: 80
        case .pwm, .battery, .controller, .motor, .trip: 100
        case .voltage: 200
        case .power: 6_000
        case .current: 80
        case .phaseCurrent: 200
        case .odometer: 20_000
        case .altitude, .ascent: 2_000
        }
    }
}

enum TileStyle: String, Codable, CaseIterable, Identifiable {
    case number, chart, bar, gauge, stack, columns, doubleGauge, wheelLog

    var id: Self { self }

    var title: String {
        switch self {
        case .number: "Число"
        case .chart: "Графики"
        case .bar: "Шкала"
        case .gauge: "Спидометр"
        case .stack: "Строки"
        case .columns: "Колонки"
        case .doubleGauge: "Двойная шкала"
        case .wheelLog: "Кластер: WheelLog"
        }
    }

    var icon: String {
        switch self {
        case .number: "number"
        case .chart: "chart.line.uptrend.xyaxis"
        case .bar: "chart.bar.xaxis"
        case .gauge: "speedometer"
        case .stack: "line.3.horizontal"
        case .columns: "rectangle.split.2x1"
        case .doubleGauge: "gauge.with.dots.needle.67percent"
        case .wheelLog: "gauge.with.needle.fill"
        }
    }

    static let wheelLogMetrics: [ConsoleMetric] = [.pwm, .battery, .controller, .wheelSpeed]

    func supports(_ metrics: [ConsoleMetric]) -> Bool {
        switch self {
        case .number, .bar, .gauge: metrics.count == 1
        case .chart, .stack: !metrics.isEmpty
        case .columns: metrics.count >= 2
        case .doubleGauge: metrics.count == 2
        case .wheelLog: metrics.count == Self.wheelLogMetrics.count && Set(metrics) == Set(Self.wheelLogMetrics)
        }
    }
}

struct ConsoleTile: Codable, Identifiable, Equatable {
    var id = UUID()
    var metrics: [ConsoleMetric]
    var style: TileStyle
    var wide = false
    var columnSpan: Int? = nil
    var rowSpan: Int? = nil

    func width(in columns: Int) -> Int {
        if style == .wheelLog { return columns }
        return min(columns, max(1, columnSpan ?? (wide ? columns : 1)))
    }

    var height: Int { style == .wheelLog ? 1 : min(3, max(1, rowSpan ?? 1)) }

    mutating func resize(columns: Int, rows: Int, limit: Int) {
        guard style != .wheelLog else { return }
        columnSpan = min(limit, max(1, columns))
        rowSpan = min(3, max(1, rows))
        wide = columnSpan == limit
    }

    mutating func setMetrics(_ metrics: [ConsoleMetric]) {
        var seen = Set<ConsoleMetric>()
        self.metrics = Array(metrics.filter { seen.insert($0).inserted }.prefix(6))
        if !style.supports(self.metrics) { style = self.metrics.count == 1 ? .number : .stack }
    }
}

struct ConsoleBoard: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var pinned: ConsoleMetric?
    var tiles: [ConsoleTile]
    var locked: Bool? = nil
    var columnCount: Int? = nil
    var columns: Int { columnCount == 3 ? 3 : 2 }

    static var standard: Self {
        Self(title: "Основной", pinned: nil, tiles: [
            ConsoleTile(metrics: [.wheelSpeed, .pwm], style: .doubleGauge, wide: true, rowSpan: 2),
            ConsoleTile(metrics: [.battery], style: .bar),
            ConsoleTile(metrics: [.voltage], style: .number),
            ConsoleTile(metrics: [.controller], style: .number),
            ConsoleTile(metrics: [.power, .current], style: .chart, columnSpan: 2, rowSpan: 2),
            ConsoleTile(metrics: [.phaseCurrent, .trip, .odometer], style: .stack, rowSpan: 2)
        ], columnCount: 3)
    }

    mutating func moveTile(_ id: UUID, to destination: UUID) {
        guard id != destination, let source = tiles.firstIndex(where: { $0.id == id }),
              let target = tiles.firstIndex(where: { $0.id == destination }) else { return }
        let tile = tiles.remove(at: source)
        tiles.insert(tile, at: target)
    }
}

struct TileGridPacking {
    struct Cell: Equatable {
        let row: Int
        let column: Int
        let width: Int
        let height: Int
    }

    let cells: [Cell]
    let rows: Int

    init(tiles: [ConsoleTile], columns: Int) {
        var occupied = [[Bool]]()
        var position = 0
        var cells = [Cell]()
        for tile in tiles {
            let width = tile.width(in: columns)
            let height = tile.height
            while true {
                let row = position / columns
                let column = position % columns
                if column + width > columns {
                    position = (row + 1) * columns
                    continue
                }
                while occupied.count < row + height {
                    occupied.append(Array(repeating: false, count: columns))
                }
                let free = (row..<(row + height)).allSatisfy { index in
                    !occupied[index][column..<(column + width)].contains(true)
                }
                if free {
                    for index in row..<(row + height) {
                        for lane in column..<(column + width) { occupied[index][lane] = true }
                    }
                    cells.append(Cell(row: row, column: column, width: width, height: height))
                    position += width
                    break
                }
                position += 1
            }
        }
        self.cells = cells
        rows = occupied.count
    }
}

struct GarageEntry: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var model: String
    var protocolKey: String
}

struct AlertCondition: Codable, Identifiable, Equatable {
    enum Comparison: String, Codable, CaseIterable, Identifiable {
        case above = "Не ниже"
        case below = "Не выше"
        var id: Self { self }
    }

    var id = UUID()
    var metric = ConsoleMetric.pwm
    var comparison = Comparison.above
    var threshold = 75.0

    func matches(_ value: Double?) -> Bool {
        guard let value, value.isFinite, threshold.isFinite else { return false }
        return comparison == .above ? value >= threshold : value <= threshold
    }
}

struct ConsoleAlert: Codable, Identifiable, Equatable {
    enum Signal: String, Codable, CaseIterable, Identifiable {
        case sound = "Звук"
        case vibration = "Вибрация"
        case voice = "Голос"
        var id: Self { self }
    }

    var id = UUID()
    var name = "Порог PWM"
    var enabled = false
    var requireAll = true
    var conditions = [AlertCondition()]
    var hold = 0.0
    var repeatEvery = 0.0
    var signal = Signal.voice
}

struct ConsoleRuleEngine {
    private struct State {
        let since: TimeInterval
        var firedAt: TimeInterval?
    }

    private var states = [UUID: State]()

    mutating func evaluate(_ rules: [ConsoleAlert], at time: TimeInterval,
                           readings: [ConsoleMetric: Double]) -> [ConsoleAlert] {
        let enabled = rules.filter(\.enabled)
        let ids = Set(enabled.map(\.id))
        states = states.filter { ids.contains($0.key) }
        var fired = [ConsoleAlert]()
        for rule in enabled {
            let checks = rule.conditions.map { $0.matches(readings[$0.metric]) }
            let satisfied = !checks.isEmpty && (rule.requireAll ? checks.allSatisfy { $0 } : checks.contains(true))
            guard satisfied else {
                states.removeValue(forKey: rule.id)
                continue
            }
            var state = states[rule.id] ?? State(since: time)
            if time - state.since >= rule.hold,
               state.firedAt.map({ rule.repeatEvery > 0 && time - $0 >= rule.repeatEvery }) ?? true {
                state.firedAt = time
                fired.append(rule)
            }
            states[rule.id] = state
        }
        return fired
    }

    mutating func stop() { states.removeAll() }
}
