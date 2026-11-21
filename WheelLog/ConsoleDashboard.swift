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
    @State private var details: TileEditSession?
    @State private var manage = false
    @State private var arranging = false

    private var profile: String { store.profile(id: wheel.connectedID, demo: wheel.demo) }
    private var board: ConsoleBoard? { store.board(for: profile) }
    private var values: [ConsoleMetric: Double] {
        ConsoleMetric.readings(wheel.telemetry, fix: wheel.demo ? nil : route.fixForLog(at: .now))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    if let board {
                        boardSelector(board)
                        if board.tiles.isEmpty {
                            Button("Добавить плитку", systemImage: "plus") { addTile(to: board) }
                                .buttonStyle(.bordered)
                                .disabled(board.locked == true)
                        }
                        TileGrid(columns: board.columns, packing: .init(tiles: board.tiles, columns: board.columns)) {
                            ForEach(board.tiles) { tile in tileButton(tile, board: board) }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
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
                        if let board { addTile(to: board) }
                    }
                    .disabled(board.map { $0.tiles.count >= 48 || $0.locked == true } ?? true)
                }
            }
        }
        .task(id: profile) { store.setupBoard(for: profile) }
        .onChange(of: board?.id) { _, _ in arranging = false }
        .sheet(item: $editor) { session in
            ConsoleTileEditor(initial: session.tile, values: values, model: wheel.modelName,
                              columns: session.columns, isNew: session.isNew) { result in save(result, session: session) }
        }
        .sheet(item: $details) { session in
            MetricDetails(initial: session.tile, columns: session.columns, wheel: wheel, route: route, samples: samples) { result in
                save(result, session: session)
            }
        }
        .sheet(isPresented: $manage) {
            if let board { BoardSettings(store: store, profile: profile, board: board) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button(action: openGarage) {
                    Label(wheel.deviceName ?? wheel.modelName, systemImage: "circle.hexagongrid.fill")
                        .font(.headline)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 4)
                if let battery = values[.battery] {
                    Label("\(ConsoleMetric.battery.reading(battery))%", systemImage: "battery.75percent")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(battery >= 20 ? RideColors.accent : Color.orange)
                }
            }
            Label(wheel.showingLastReading ? "Нет сигнала · последние показания"
                  : wheel.demo ? "Демо · Sherman S" : wheel.state == .live ? wheel.modelName + " · на связи" : wheel.status,
                  systemImage: wheel.showingLastReading ? "exclamationmark.circle" : "antenna.radiowaves.left.and.right")
                .font(.caption)
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
        .padding(10)
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
                    store.addBoard(.init(title: "Моя панель", tiles: [], columnCount: 3), profile: profile)
                }
                Button("Панель с компактными приборами", systemImage: "square.grid.3x3") {
                    var next = ConsoleBoard.standard
                    next.title = "Компактная"
                    store.addBoard(next, profile: profile)
                }
            } label: {
                Label(active.title, systemImage: "rectangle.grid.2x2")
                    .font(.subheadline.weight(.semibold))
            }
            Spacer()
            if active.locked != true, !active.tiles.isEmpty {
                Button(arranging ? "Завершить раскладку" : "Изменить раскладку",
                       systemImage: arranging ? "checkmark.circle.fill" : "square.grid.3x3") {
                    withAnimation(.easeInOut(duration: 0.18)) { arranging.toggle() }
                }
                .labelStyle(.iconOnly)
                .padding(.horizontal, 4)
            }
            Button(active.locked == true ? "Разблокировать плитки" : "Заблокировать плитки",
                   systemImage: active.locked == true ? "lock.fill" : "lock.open") {
                var next = active
                next.locked = active.locked != true
                arranging = false
                store.update(next, profile: profile)
            }
            .labelStyle(.iconOnly)
            .padding(.horizontal, 4)
            Button("Настройки панели", systemImage: "slider.horizontal.3") { manage = true }
                .labelStyle(.iconOnly)
                .padding(.horizontal, 4)
                .disabled(active.locked == true)
        }
    }

    private func tileButton(_ tile: ConsoleTile, board: ConsoleBoard) -> some View {
        let card = ConsoleTileCard(tile: tile, values: values, series: samples.series,
                                   extrema: wheel.extrema, model: wheel.modelName)
        return Group {
            if arranging {
                arrangementTile(tile, board: board, card: card)
            } else if board.locked == true {
                card
            } else {
                Button {
                    details = TileEditSession(profile: profile, boardID: board.id, columns: board.columns, tile: tile, isNew: false)
                } label: { card }
                .buttonStyle(.plain)
                .accessibilityHint("Открывает подробные показания")
            }
        }
    }

    private func arrangementTile(_ tile: ConsoleTile, board: ConsoleBoard, card: ConsoleTileCard) -> some View {
        card
            .overlay(alignment: .topLeading) {
                Image(systemName: "line.3.horizontal")
                    .frame(width: 40, height: 40)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .draggable(tile.id.uuidString)
                    .accessibilityLabel("Переместить плитку")
            }
            .overlay(alignment: .bottomTrailing) {
                if tile.style != .wheelLog {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .frame(width: 40, height: 40)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .gesture(DragGesture(minimumDistance: 12).onEnded { drag in
                            resize(tile, board: board, offset: drag.translation)
                        })
                        .accessibilityLabel("Изменить размер плитки")
                }
            }
            .dropDestination(for: String.self) { items, _ in
                guard let text = items.first, let id = UUID(uuidString: text), id != tile.id,
                      var current = store.board(for: profile), current.id == board.id,
                      current.tiles.contains(where: { $0.id == id }) else { return false }
                current.moveTile(id, to: tile.id)
                withAnimation(.easeInOut(duration: 0.18)) { store.update(current, profile: profile) }
                return true
            }
    }

    private func resize(_ tile: ConsoleTile, board: ConsoleBoard, offset: CGSize) {
        guard var current = store.board(for: profile), current.id == board.id,
              let index = current.tiles.firstIndex(where: { $0.id == tile.id }) else { return }
        let width = tile.width(in: board.columns) + Int((offset.width / 84).rounded())
        let height = tile.height + Int((offset.height / 72).rounded())
        current.tiles[index].resize(columns: width, rows: height, limit: board.columns)
        if current.tiles[index] != tile {
            withAnimation(.easeInOut(duration: 0.18)) { store.update(current, profile: profile) }
        }
    }

    private func addTile(to board: ConsoleBoard) {
        editor = TileEditSession(profile: profile, boardID: board.id, columns: board.columns,
                                 tile: .init(metrics: [.wheelSpeed], style: .number),
                                 isNew: true)
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

private struct TileGrid: Layout {
    let columns: Int
    let packing: TileGridPacking
    private let spacing: CGFloat = 8
    private let minimumRowHeight: CGFloat = 66

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        let dimensions = measure(width: width, subviews: subviews)
        return CGSize(width: width, height: max(0, (dimensions.offsets.last ?? 0) - spacing))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let dimensions = measure(width: bounds.width, subviews: subviews)
        for (cell, subview) in zip(packing.cells, subviews) {
            let cellWidth = spanWidth(cell.width, columnWidth: dimensions.columnWidth)
            let cellHeight = dimensions.offsets[cell.row + cell.height] - dimensions.offsets[cell.row] - spacing
            subview.place(
                at: CGPoint(x: bounds.minX + (dimensions.columnWidth + spacing) * CGFloat(cell.column),
                            y: bounds.minY + dimensions.offsets[cell.row]),
                anchor: .topLeading, proposal: ProposedViewSize(width: cellWidth, height: cellHeight)
            )
        }
    }

    private func measure(width: CGFloat, subviews: Subviews) -> (columnWidth: CGFloat, offsets: [CGFloat]) {
        let columnWidth = max(1, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        var heights = Array(repeating: minimumRowHeight, count: packing.rows)
        for (cell, subview) in zip(packing.cells, subviews) {
            let required = subview.sizeThatFits(
                ProposedViewSize(width: spanWidth(cell.width, columnWidth: columnWidth), height: nil)
            ).height
            let perRow = (required - spacing * CGFloat(cell.height - 1)) / CGFloat(cell.height)
            for index in cell.row..<(cell.row + cell.height) { heights[index] = max(heights[index], perRow) }
        }
        var offsets: [CGFloat] = [0]
        for height in heights { offsets.append(offsets[offsets.count - 1] + height + spacing) }
        return (columnWidth, offsets)
    }

    private func spanWidth(_ span: Int, columnWidth: CGFloat) -> CGFloat {
        columnWidth * CGFloat(span) + spacing * CGFloat(span - 1)
    }
}

private struct TileEditSession: Identifiable {
    let id = UUID()
    let profile: String
    let boardID: UUID
    let columns: Int
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
                VStack(alignment: .leading, spacing: 7) { content }
                    .padding(10)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading)
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
            HStack(alignment: .top, spacing: 6) {
                ForEach(tile.metrics) { metric in
                    InstrumentDial(metric: metric, value: values[metric],
                                   peak: metric == .wheelSpeed ? extrema.speed : metric == .pwm ? extrema.pwm : nil,
                                   fraction: fraction(metric))
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

private struct InstrumentDial: View {
    let metric: ConsoleMetric
    let value: Double?
    let peak: Double?
    let fraction: Double

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().trim(from: 0, to: 0.72)
                    .stroke(RideColors.line, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(140))
                Circle().trim(from: 0, to: 0.72 * fraction)
                    .stroke(metric.tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(140))
                VStack(spacing: 1) {
                    Text(metric.reading(value))
                        .font(.system(.title, design: .monospaced).weight(.semibold))
                        .foregroundStyle(metric.tint)
                        .lineLimit(1).minimumScaleFactor(0.45)
                    Text(metric.unit).font(.caption2).foregroundStyle(RideColors.muted)
                }
                .padding(.horizontal, 7)
            }
            .padding(4)
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 102)
            Text(metric.title).font(.caption2.weight(.medium)).lineLimit(1).minimumScaleFactor(0.75)
            if let peak {
                Text("Макс. \(metric.reading(peak))").font(.caption2.monospacedDigit()).foregroundStyle(RideColors.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
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

private struct MetricDetails: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var wheel: WheelConnection
    @ObservedObject var route: RouteRecorder
    @ObservedObject var samples: ConsoleSamples
    let save: (ConsoleTile?) -> Void
    let columns: Int
    @State private var tile: ConsoleTile
    @State private var metric: ConsoleMetric
    @State private var editing = false
    @State private var removed = false

    init(initial: ConsoleTile, columns: Int, wheel: WheelConnection, route: RouteRecorder,
         samples: ConsoleSamples, save: @escaping (ConsoleTile?) -> Void) {
        self.wheel = wheel
        self.route = route
        self.samples = samples
        self.save = save
        self.columns = columns
        _tile = State(initialValue: initial)
        _metric = State(initialValue: initial.metrics.first ?? .wheelSpeed)
    }

    private var values: [ConsoleMetric: Double] {
        ConsoleMetric.readings(wheel.telemetry, fix: wheel.demo ? nil : route.fixForLog(at: .now))
    }

    var body: some View {
        RideScreen(title: "Подробные показания", showsClose: true) {
            if tile.metrics.count > 1 {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(tile.metrics) { item in
                            Button(item.title) { metric = item }
                                .buttonStyle(.bordered)
                                .tint(item == metric ? item.tint : RideColors.muted)
                                .accessibilityAddTraits(item == metric ? .isSelected : [])
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            RidePanel {
                Text(metric.title).font(.headline)
                Text("\(metric.reading(values[metric])) \(metric.unit)")
                    .font(.system(.largeTitle, design: .monospaced))
                    .foregroundStyle(metric.tint)
                if wheel.showingLastReading {
                    Label("Нет сигнала · последнее показание", systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.red)
                }
            }
            let history = samples.series[metric] ?? []
            let present = history.compactMap { $0 }
            RidePanel {
                Text("Последние показания").font(.headline)
                if present.isEmpty {
                    Text("Данных пока нет").foregroundStyle(RideColors.muted)
                } else {
                    MetricSparkline(values: history, color: metric.tint)
                        .frame(height: 130)
                        .padding(.vertical, 8)
                    HStack {
                        statistic("Мин.", value: present.min())
                        statistic("Среднее", value: present.reduce(0, +) / Double(present.count))
                        statistic("Макс.", value: present.max())
                    }
                }
            }
            Button("Настройки плитки", systemImage: "slider.horizontal.3") { editing = true }
                .buttonStyle(.borderedProminent)
        }
        .sheet(isPresented: $editing, onDismiss: { if removed { dismiss() } }) {
            ConsoleTileEditor(initial: tile, values: values, model: wheel.modelName, columns: columns, isNew: false) { result in
                save(result)
                if let result {
                    tile = result
                    if !result.metrics.contains(metric), let first = result.metrics.first { metric = first }
                } else {
                    removed = true
                }
            }
        }
    }

    private func statistic(_ title: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(RideColors.muted)
            Text(metric.reading(value)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ConsoleTileEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tile: ConsoleTile
    let values: [ConsoleMetric: Double]
    let model: String
    let columns: Int
    let isNew: Bool
    let save: (ConsoleTile?) -> Void

    init(initial: ConsoleTile, values: [ConsoleMetric: Double], model: String,
         columns: Int, isNew: Bool, save: @escaping (ConsoleTile?) -> Void) {
        _tile = State(initialValue: initial)
        self.values = values
        self.model = model
        self.columns = columns
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
                Section("Метрики") {
                    ForEach(ConsoleMetric.allCases) { metric in
                        Toggle(isOn: Binding(
                            get: { tile.metrics.contains(metric) },
                            set: { selected in
                                tile.setMetrics(selected ? tile.metrics + [metric] : tile.metrics.filter { $0 != metric })
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(metric.title)
                                Text("\(metric.reading(values[metric])) \(metric.unit)")
                                    .font(.caption.monospacedDigit()).foregroundStyle(metric.tint)
                            }
                        }
                        .disabled(!tile.metrics.contains(metric) && tile.metrics.count >= 6)
                    }
                }
                Section("Оформление") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(TileStyle.allCases) { style in styleCard(style) }
                    }
                    if !TileStyle.wheelLog.supports(tile.metrics) {
                        Text("Для WheelLog выберите PWM, заряд, температуру контроллера и скорость колеса.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if tile.style != .wheelLog {
                        Stepper("Ширина · \(tile.width(in: columns))", value: Binding(
                            get: { tile.width(in: columns) },
                            set: { tile.resize(columns: $0, rows: tile.height, limit: columns) }
                        ), in: 1...columns)
                        Stepper("Высота · \(tile.height)", value: Binding(
                            get: { tile.height },
                            set: { tile.resize(columns: tile.width(in: columns), rows: $0, limit: columns) }
                        ), in: 1...3)
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

    private func styleCard(_ style: TileStyle) -> some View {
        Button {
            tile.style = style
        } label: {
            VStack(spacing: 5) {
                Image(systemName: style.icon).font(.title3)
                Text(style.title).font(.caption.weight(.medium)).lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(tile.style == style ? RideColors.accent.opacity(0.17) : RideColors.surface,
                        in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(style.supports(tile.metrics) ? RideColors.instrument : RideColors.muted.opacity(0.5))
        }
        .buttonStyle(.plain)
        .disabled(!style.supports(tile.metrics))
        .accessibilityAddTraits(tile.style == style ? .isSelected : [])
    }
}
