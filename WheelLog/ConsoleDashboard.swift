import SwiftUI

extension ConsoleMetric {
    static func readings(_ frame: Telemetry, fix: RouteFix?) -> [Self: Double] {
        let readings: [Self: Double?] = [
            .wheelSpeed: frame.speed.map(abs), .gpsSpeed: fix?.speed, .pwm: frame.pwm,
            .battery: frame.battery, .controller: frame.temperature, .motor: frame.motorTemperature,
            .voltage: frame.voltage, .power: frame.power, .current: frame.current,
            .phaseCurrent: frame.phaseCurrent, .trip: frame.trip, .odometer: frame.odometer,
            .altitude: fix?.altitude, .ascent: fix?.ascent
        ]
        return readings.compactMapValues { value in
            guard let value, value.isFinite else { return nil }
            return value
        }
    }

    var tint: Color {
        switch self {
        case .pwm, .power: .orange
        case .controller, .motor: .pink
        case .gpsSpeed, .wheelSpeed: .cyan
        case .altitude, .ascent: .purple
        default: RideColors.accent
        }
    }
}

struct ConsoleDashboard: View {
    @ObservedObject var store: ConsoleStore
    @ObservedObject var wheel: WheelConnection
    @ObservedObject var route: RouteRecorder
    @ObservedObject var samples: ConsoleSamples
    let camera: () -> Void
    let openGarage: () -> Void

    @State private var editor: TileEditSession?
    @State private var manage = false

    private var profile: String { store.profile(id: wheel.connectedID, demo: wheel.demo) }
    private var board: ConsoleBoard? { store.board(for: profile) }
    private var values: [ConsoleMetric: Double] {
        ConsoleMetric.readings(wheel.telemetry, fix: wheel.demo ? nil : route.fixForLog(at: .now))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if let board {
                        boardSelector(board)
                        if board.tiles.isEmpty {
                            Button("Добавить плитку", systemImage: "plus") { edit(nil, board: board) }
                                .buttonStyle(.bordered)
                        }
                        ForEach(tileRows(board.tiles)) { row in
                            HStack(alignment: .top, spacing: 10) {
                                ForEach(row.tiles) { tile in tileButton(tile, board: board) }
                                if row.tiles.count == 1, !row.first.wide, row.first.style != .wheelLog {
                                    Color.clear.frame(maxWidth: .infinity)
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(RideColors.background.ignoresSafeArea())
            .navigationTitle("Приборы")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Камера с телеметрией", systemImage: "video", action: camera)
                    Button("Добавить плитку", systemImage: "plus") {
                        if let board { edit(nil, board: board) }
                    }
                    .disabled(board.map { $0.tiles.count >= 48 } ?? true)
                }
            }
        }
        .task(id: profile) { store.setupBoard(for: profile) }
        .sheet(item: $editor) { session in
            ConsoleTileEditor(initial: session.tile, values: values, model: wheel.modelName,
                              isNew: session.isNew) { result in save(result, session: session) }
        }
        .sheet(isPresented: $manage) {
            if let board { BoardSettings(store: store, profile: profile, board: board) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button(action: openGarage) {
                HStack {
                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.title3)
                        .foregroundStyle(RideColors.accent)
                    Text(wheel.modelName).font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Label(wheel.showingLastReading ? "Нет сигнала · последние показания"
                  : wheel.demo ? "Демонстрация" : wheel.status,
                  systemImage: wheel.showingLastReading ? "exclamationmark.circle" : "antenna.radiowaves.left.and.right")
                .font(.subheadline)
                .foregroundStyle(wheel.showingLastReading ? Color.red : RideColors.muted)
            if let metric = board?.pinned, let value = values[metric] {
                Text("\(metric.title)  \(metric.reading(value)) \(metric.unit)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(metric.tint)
            }
            if wheel.state == .live, let message = samples.lastAlert {
                Label(message, systemImage: "bell.badge").font(.subheadline).foregroundStyle(.orange)
            }
        }
        .padding(14)
        .background(RideColors.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func boardSelector(_ active: ConsoleBoard) -> some View {
        HStack {
            Menu {
                ForEach(store.boards(for: profile)) { item in
                    Button(item.title, systemImage: item.id == active.id ? "checkmark" : "rectangle.grid.2x2") {
                        store.settings.activeBoards[profile] = item.id
                    }
                }
                Button("Новая панель", systemImage: "plus") {
                    store.addBoard(.init(title: "Моя панель", tiles: []), profile: profile)
                }
            } label: {
                Label(active.title, systemImage: "rectangle.grid.2x2")
                    .font(.subheadline.weight(.semibold))
            }
            Spacer()
            Button("Настройки панели", systemImage: "slider.horizontal.3") { manage = true }
                .labelStyle(.iconOnly)
                .padding(.horizontal, 4)
        }
    }

    private func tileButton(_ tile: ConsoleTile, board: ConsoleBoard) -> some View {
        Button { edit(tile, board: board) } label: {
            ConsoleTileCard(tile: tile, values: values, series: samples.series,
                            extrema: wheel.extrema, model: wheel.modelName)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Открывает настройки плитки")
    }

    private func tileRows(_ tiles: [ConsoleTile]) -> [TileRow] {
        var rows = [TileRow]()
        for tile in tiles {
            if !tile.wide, tile.style != .wheelLog,
               let last = rows.last, last.second == nil, !last.first.wide, last.first.style != .wheelLog {
                rows[rows.count - 1].second = tile
            } else {
                rows.append(TileRow(first: tile))
            }
        }
        return rows
    }

    private func edit(_ tile: ConsoleTile?, board: ConsoleBoard) {
        editor = TileEditSession(profile: profile, boardID: board.id,
                                 tile: tile ?? .init(metrics: [.wheelSpeed], style: .number),
                                 isNew: tile == nil)
    }

    private func save(_ tile: ConsoleTile?, session: TileEditSession) {
        guard var board = store.boards(for: session.profile).first(where: { $0.id == session.boardID }) else { return }
        if session.isNew, let tile { board.tiles.append(tile) }
        else if let index = board.tiles.firstIndex(where: { $0.id == session.tile.id }) {
            if let tile { board.tiles[index] = tile }
            else { board.tiles.remove(at: index) }
        }
        store.update(board, profile: session.profile)
    }
}

private struct TileRow: Identifiable {
    let first: ConsoleTile
    var second: ConsoleTile?
    var id: UUID { first.id }
    var tiles: [ConsoleTile] { [first, second].compactMap { $0 } }
}

private struct TileEditSession: Identifiable {
    let id = UUID()
    let profile: String
    let boardID: UUID
    let tile: ConsoleTile
    let isNew: Bool
}

struct ConsoleTileCard: View {
    let tile: ConsoleTile
    let values: [ConsoleMetric: Double]
    var series = [ConsoleMetric: [Double?]]()
    var extrema = RideExtrema()
    let model: String

    var body: some View {
        Group {
            if tile.style == .wheelLog {
                classic
            } else {
                VStack(alignment: .leading, spacing: 9) { content }
                    .padding(14)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
        .background(tile.style == .wheelLog ? ClassicDialColors.background : RideColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(RideColors.line).allowsHitTesting(false) }
    }

    private var classic: some View {
        let frame = Telemetry(speed: values[.wheelSpeed], pwm: values[.pwm],
                              battery: values[.battery], temperature: values[.controller])
        return ClassicSpeedometer(frame: frame, extrema: extrema, model: model,
                                   quantity: .pwm, showPWM: true, swapSpeedPWM: true)
            .aspectRatio(1.24, contentMode: .fit)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Кластер WheelLog")
            .accessibilityValue(tile.metrics.map { metric in
                "\(metric.title) \(metric.reading(values[metric])) \(metric.unit)"
            }.joined(separator: ", "))
    }

    @ViewBuilder private var content: some View {
        switch tile.style {
        case .number:
            if let metric = tile.metrics.first { number(metric) }
        case .bar:
            if let metric = tile.metrics.first {
                number(metric)
                ProgressView(value: fraction(metric)).tint(metric.tint)
                    .accessibilityHidden(true)
            }
        case .gauge, .doubleGauge:
            HStack(alignment: .top, spacing: 16) {
                ForEach(tile.metrics) { metric in
                    VStack(spacing: 8) {
                        Gauge(value: fraction(metric)) {
                            Text(metric.title).font(.caption).lineLimit(1)
                        } currentValueLabel: {
                            Text(metric.reading(values[metric])).font(.caption.monospacedDigit())
                        }
                        .gaugeStyle(.accessoryCircular)
                        .tint(metric.tint)
                        Text(metric.title).font(.caption).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        case .columns:
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(tile.metrics) { metric in
                    VStack {
                        number(metric, small: true)
                        GeometryReader { proxy in
                            Capsule().fill(metric.tint)
                                .frame(height: proxy.size.height * fraction(metric))
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                        .frame(height: 36)
                        .background(RideColors.line, in: Capsule())
                        .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        case .chart, .stack:
            ForEach(tile.metrics) { metric in
                HStack {
                    Text(metric.title).font(.caption).foregroundStyle(RideColors.muted)
                    Spacer(minLength: 4)
                    measurement(metric).font(.subheadline)
                }
                if tile.style == .chart {
                    MetricSparkline(values: series[metric] ?? [], color: metric.tint)
                        .frame(height: 26)
                }
            }
        case .wheelLog:
            EmptyView()
        }
    }

    private func number(_ metric: ConsoleMetric, small: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(metric.title).font(.caption).foregroundStyle(RideColors.muted).lineLimit(2)
            measurement(metric).font(small ? .caption : .title2.weight(.semibold))
        }
    }

    private func measurement(_ metric: ConsoleMetric) -> some View {
        Text("\(metric.reading(values[metric])) \(metric.unit)")
            .monospacedDigit().foregroundStyle(metric.tint).lineLimit(1).minimumScaleFactor(0.5)
    }

    private func fraction(_ metric: ConsoleMetric) -> Double {
        min(1, max(0, (values[metric] ?? 0) / metric.maximum))
    }
}

private struct MetricSparkline: View {
    let values: [Double?]
    let color: Color

    var body: some View {
        Canvas { context, size in
            let present = values.compactMap { $0 }
            guard let minimum = present.min(), let maximum = present.max(), values.count > 1 else { return }
            let range = maximum - minimum
            var path = Path()
            var joining = false
            for (index, value) in values.enumerated() {
                guard let value else { joining = false; continue }
                let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
                let fraction = range > 0 ? (value - minimum) / range : 0.5
                let y = 2 + (size.height - 4) * (1 - fraction)
                if joining { path.addLine(to: .init(x: x, y: y)) }
                else { path.move(to: .init(x: x, y: y)) }
                joining = true
            }
            context.stroke(path, with: .color(color), style: .init(lineWidth: 1.5, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

private struct ConsoleTileEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tile: ConsoleTile
    let values: [ConsoleMetric: Double]
    let model: String
    let isNew: Bool
    let save: (ConsoleTile?) -> Void

    init(initial: ConsoleTile, values: [ConsoleMetric: Double], model: String,
         isNew: Bool, save: @escaping (ConsoleTile?) -> Void) {
        _tile = State(initialValue: initial)
        self.values = values
        self.model = model
        self.isNew = isNew
        self.save = save
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Предпросмотр") {
                    ConsoleTileCard(tile: tile, values: values, model: model)
                        .listRowInsets(EdgeInsets())
                }
                Section("Оформление") {
                    ForEach(TileStyle.allCases) { style in styleRow(style) }
                    if !TileStyle.wheelLog.supports(tile.metrics) {
                        Text("Для WheelLog выберите PWM, заряд, температуру контроллера и скорость колеса.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Toggle("На всю ширину", isOn: $tile.wide).disabled(tile.style == .wheelLog)
                }
                Section("Метрики") {
                    ForEach(ConsoleMetric.allCases) { metric in
                        Toggle(metric.title, isOn: Binding(
                            get: { tile.metrics.contains(metric) },
                            set: { selected in
                                tile.setMetrics(selected ? tile.metrics + [metric] : tile.metrics.filter { $0 != metric })
                            }
                        ))
                        .disabled(!tile.metrics.contains(metric) && tile.metrics.count >= 6)
                    }
                }
                if !isNew {
                    Section {
                        Button("Удалить плитку", role: .destructive) { save(nil); dismiss() }
                    }
                }
            }
            .navigationTitle("Настройка плитки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { save(tile); dismiss() }.disabled(tile.metrics.isEmpty)
                }
            }
        }
    }

    private func styleRow(_ style: TileStyle) -> some View {
        Button {
            tile.style = style
            if style == .wheelLog { tile.wide = true }
        } label: {
            HStack {
                Label(style.title, systemImage: style.icon)
                Spacer()
                if tile.style == style { Image(systemName: "checkmark") }
            }
            .contentShape(Rectangle())
        }
        .disabled(!style.supports(tile.metrics))
        .accessibilityAddTraits(tile.style == style ? .isSelected : [])
    }
}
