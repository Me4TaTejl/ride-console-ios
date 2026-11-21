import Foundation

@main
struct ShermanProtocolChecks {
    static func main() {
        var decoder = ShermanProtocol()
        let packet = frame()
        precondition(decoder.receive(Data([0x00, 0xDC, 0x64]) + Data(packet.prefix(1))).isEmpty)
        precondition(decoder.receive(Data(packet[1..<20])).isEmpty)
        let results = decoder.receive(Data(packet[20...]) + Data(packet))
        precondition(results.count == 2)
        let decoded = results[0]
        precondition(decoded.version == "003.0.15")
        precondition(decoded.pedalMode == .medium)
        precondition(decoded.telemetry.speed == -31.2)
        precondition(decoded.telemetry.voltage == 95.5)
        precondition(decoded.telemetry.battery == 76)
        precondition(decoded.telemetry.pwm == 41.25)
        precondition(decoded.telemetry.phaseCurrent == -18.4)
        precondition(abs((decoded.telemetry.power ?? 0) + 724.845) < 0.001)
        precondition(decoded.telemetry.odometer == 567.891)
        precondition(decoded.telemetry.trip == 3.21)
        precondition(decoded.telemetry.temperature == 31.27)
        precondition(decoded.speedAlarm == 58.0 && decoded.tiltBack == 65.5)

        var otherWheel = packet
        otherWheel[28] = 0x13
        otherWheel[29] = 0x88
        precondition(decoder.receive(Data(otherWheel)).isEmpty)

        let checked: [UInt8] = [
            0xDC, 0x5A, 0x5C, 0x26, 0x25, 0x4E, 0xFE, 0xC8, 0x0C, 0x8A, 0x00, 0x00,
            0xAA, 0x53, 0x00, 0x08, 0xFF, 0x48, 0x0C, 0x37, 0x00, 0x00, 0x00, 0x00,
            0x02, 0x44, 0x02, 0x8F, 0x0B, 0xC7, 0x00, 0x01, 0x00, 0x00, 0x10, 0x1D,
            0x00, 0x00, 0xFB, 0x6D, 0xAE, 0x7A
        ]
        var corrupted = checked
        corrupted[8] ^= 1
        precondition(decoder.receive(Data(checked)).count == 1)
        precondition(decoder.receive(Data(corrupted) + Data(packet) + Data(checked)).count == 1)

        precondition(ShermanProtocol.light(on: true) == Data("SetLightON".utf8))
        precondition(ShermanProtocol.light(on: false) == Data("SetLightOFF".utf8))
        precondition(ShermanProtocol.pedals(.soft) == Data("SETs".utf8))
        precondition(ShermanProtocol.pedals(.medium) == Data("SETm".utf8))
        precondition(ShermanProtocol.pedals(.hard) == Data("SETh".utf8))
        print("ShermanProtocol checks passed")
        checkAscent()
        print("Route elevation gain checks passed")
        checkConsole()
        print("Dashboard tile and alert checks passed")
    }

    private static func checkConsole() {
        let required = TileStyle.wheelLogMetrics
        precondition(TileStyle.wheelLog.supports(Array(required.reversed())))
        precondition(!TileStyle.wheelLog.supports([.pwm, .battery, .controller, .gpsSpeed]))
        precondition(!TileStyle.wheelLog.supports(required + [.gpsSpeed]))
        var tile = ConsoleTile(metrics: required, style: .wheelLog)
        tile.setMetrics([.pwm, .battery, .controller])
        precondition(tile.style == .stack)

        var board = ConsoleBoard.standard
        let packing = TileGridPacking(tiles: board.tiles, columns: board.columns)
        precondition(packing.rows == 5)
        precondition(packing.cells.first == .init(row: 0, column: 0, width: 3, height: 2))
        precondition(packing.cells.last == .init(row: 3, column: 2, width: 1, height: 2))
        let first = board.tiles[0].id
        let last = board.tiles[5].id
        board.moveTile(first, to: last)
        precondition(board.tiles.last?.id == first)

        var rule = ConsoleAlert()
        rule.enabled = true
        rule.hold = 2
        rule.repeatEvery = 3
        rule.conditions.append(.init(metric: .wheelSpeed, comparison: .above, threshold: 30))
        var alerts = ConsoleRuleEngine()
        let readings: [ConsoleMetric: Double] = [.pwm: 80, .wheelSpeed: 35]
        precondition(alerts.evaluate([rule], at: 1, readings: readings).isEmpty)
        precondition(alerts.evaluate([rule], at: 3, readings: readings) == [rule])
        precondition(alerts.evaluate([rule], at: 5, readings: readings).isEmpty)
        precondition(alerts.evaluate([rule], at: 6, readings: readings) == [rule])
        precondition(alerts.evaluate([rule], at: 7, readings: [.pwm: 80, .gpsSpeed: 60]).isEmpty)
        precondition(alerts.evaluate([rule], at: 9, readings: readings).isEmpty)
        precondition(alerts.evaluate([rule], at: 11, readings: readings) == [rule])
    }

    private static func checkAscent() {
        let start = Date(timeIntervalSince1970: 0)
        var ascent = RouteAscent()
        let altitudes: [Double] = [100, 400, 100, 110, 110, 100, 100, 115, 115]
        for (second, altitude) in altitudes.enumerated() {
            ascent.add(altitude: altitude, accuracy: 5, at: start.addingTimeInterval(Double(second)))
            if second == 2 { precondition(ascent.gain == 0) }
            if second == 6 { precondition(ascent.gain == 10) }
        }
        precondition(ascent.gain == 25)
        ascent.add(altitude: 200, accuracy: 80, at: start.addingTimeInterval(9))
        for second in 100...102 {
            ascent.add(altitude: 400, accuracy: 5, at: start.addingTimeInterval(Double(second)))
        }
        precondition(ascent.gain == 25)
    }

    private static func frame() -> [UInt8] {
        [
            0xDC, 0x5A, 0x5C, 0x22, 0x25, 0x4E, 0xFE, 0xC8, 0x0C, 0x8A, 0x00, 0x00,
            0xAA, 0x53, 0x00, 0x08, 0xFF, 0x48, 0x0C, 0x37, 0x00, 0x00, 0x00, 0x00,
            0x02, 0x44, 0x02, 0x8F, 0x0B, 0xC7, 0x00, 0x01, 0x00, 0x00, 0x10, 0x1D,
            0x00, 0x00
        ]
    }
}
