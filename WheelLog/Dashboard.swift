import SwiftUI
import UIKit

enum ClassicTypeface {
    static let name = "Wheellog-Regular"

    static func font(_ size: CGFloat) -> Font {
        .custom(name, fixedSize: size)
    }
}

enum ClassicNumber {
    static func text(_ value: Double?, places: Int = 0, minimum: Int = 1) -> String {
        guard let value else { return "—" }
        let digits = minimum + (places == 0 ? 0 : places + 1)
        return String(format: "%0\(digits).\(places)f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    static func reading(_ value: Double?, places: Int = 0, unit: String) -> String {
        text(value, places: places) + (unit == "%" ? "" : " ") + unit
    }
}

enum DialQuantity: String, CaseIterable, Identifiable {
    case speed = "Скорость"
    case current = "Ток"
    case pwm = "PWM"
    case phaseCurrent = "Фазный ток"
    var id: Self { self }

    func value(_ frame: Telemetry) -> Double? {
        switch self {
        case .speed: frame.speed
        case .current: frame.current
        case .pwm: frame.pwm
        case .phaseCurrent: frame.phaseCurrent
        }
    }

    var scale: Double {
        switch self {
        case .speed: 60
        case .current: 100
        case .pwm: 100
        case .phaseCurrent: 200
        }
    }
}

struct ClassicSpeedometer: View {
    // Classic dial geometry follows WheelLog.Android 3.2.9 (GPL-3.0).
    let frame: Telemetry
    let extrema: RideExtrema
    let model: String
    let quantity: DialQuantity
    let showPWM: Bool
    let swapSpeedPWM: Bool

    private let segmentStep = 2.25
    private let start = 144.0
    private let end = 396.0

    var body: some View {
        Canvas { graphics, size in
            let side = size.width
            let center = CGPoint(x: side / 2, y: side / 2)
            let outerWidth = side / 8
            let innerWidth = outerWidth * 0.60
            let outer = (side - outerWidth) / 2
            let inner = outer - (outerWidth + innerWidth) / 2 - side * 0.012

            stroke(graphics, center, outer, from: start, to: end, width: outerWidth, color: ClassicDialColors.arc)
            stroke(graphics, center, inner, from: start, to: 234, width: innerWidth, color: ClassicDialColors.arc)
            stroke(graphics, center, inner, from: 306, to: end, width: innerWidth, color: ClassicDialColors.arc)

            let dial = quantity.value(frame) ?? 0
            let dialCount = steps(abs(dial) / quantity.scale, in: 112)
            let dialColor = quantity == .pwm ? pwmColor : (dial < 0 ? ClassicDialColors.dialNegative : ClassicDialColors.dialPositive)
            drawSegments(graphics, center, outer, width: outerWidth, first: 0, last: dialCount) { _ in dialColor }

            if let battery = frame.battery {
                let count = steps(battery / 100, in: 40)
                let low = steps((extrema.lowestBattery ?? battery) / 100, in: 40)
                drawSegments(graphics, center, inner, width: innerWidth, first: 0, last: count) { index in
                    index >= low ? ClassicDialColors.batteryLow : ClassicDialColors.battery
                }
                let boundary = start + Double(count) * segmentStep
                place(graphics, text: ClassicNumber.text(battery, minimum: 2) + "%", size: side * 0.042,
                      at: point(center, inner, boundary + 0.6), rotation: boundary - 180, color: ClassicDialColors.instrument)
                place(graphics, text: "true", size: side * 0.037, at: point(center, inner, start - 5),
                      rotation: start - 185, color: ClassicDialColors.instrument)
            }

            if let temperature = frame.temperature {
                let count = steps(temperature / 80, in: 40)
                drawSegments(graphics, center, inner, width: innerWidth, first: 112 - count, last: 112) { _ in ClassicDialColors.temperature }
                let boundary = end - Double(count) * segmentStep
                place(graphics, text: ClassicNumber.text(temperature) + "°C", size: side * 0.042,
                      at: point(center, inner, boundary - 2), rotation: boundary - 360, color: ClassicDialColors.instrument)
                if let maximum = extrema.temperature {
                    place(graphics, text: ClassicNumber.text(maximum) + "°C", size: side * 0.042,
                          at: point(center, inner, 310), rotation: -50, color: ClassicDialColors.instrument)
                }
            }

            drawModel(graphics, center: center, radius: inner - side * 0.037, size: side * 0.063)
            let speed = frame.speed.map(abs)
            let displayedSpeed = ClassicNumber.text(speed, places: (speed ?? 0) < 10 ? 1 : 0)
            let primary = swapSpeedPWM ? ClassicNumber.text(frame.pwm) : displayedSpeed
            place(graphics, text: primary, size: side * 0.326,
                  at: CGPoint(x: center.x, y: center.y - side * 0.009), color: swapSpeedPWM ? pwmColor : .white)

            let subheading: String
            if showPWM && !swapSpeedPWM {
                subheading = "\(ClassicNumber.text(frame.pwm, minimum: 2))% / \(ClassicNumber.text(extrema.pwm, minimum: 2))%"
            } else if swapSpeedPWM {
                subheading = "\(displayedSpeed) км/ч"
            } else {
                subheading = "км/ч"
            }
            place(graphics, text: subheading, size: side * 0.080,
                  at: CGPoint(x: center.x, y: center.y + side * 0.22), color: ClassicDialColors.instrument)
        }
        .accessibilityLabel("Скорость \(ClassicNumber.text(frame.speed.map(abs), places: 1)) км/ч")
        .accessibilityValue("PWM \(ClassicNumber.text(frame.pwm)) процентов")
    }

    private var pwmColor: Color {
        switch frame.pwm ?? 0 {
        case 90...: ClassicDialColors.dialPositive
        case 75...: ClassicDialColors.batteryLow
        default: ClassicDialColors.instrument
        }
    }

    private func steps(_ fraction: Double, in count: Int) -> Int {
        Int((min(1, max(0, fraction)) * Double(count)).rounded())
    }

    private func drawSegments(_ graphics: GraphicsContext, _ center: CGPoint, _ radius: CGFloat, width: CGFloat,
                              first: Int, last: Int, color: (Int) -> Color) {
        guard first < last else { return }
        for index in first..<last {
            let angle = start + Double(index) * segmentStep
            stroke(graphics, center, radius, from: angle, to: angle + 1.5, width: width, color: color(index))
        }
    }

    private func stroke(_ graphics: GraphicsContext, _ center: CGPoint, _ radius: CGFloat,
                        from: Double, to: Double, width: CGFloat, color: Color) {
        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false)
        graphics.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .butt))
    }

    private func drawModel(_ graphics: GraphicsContext, center: CGPoint, radius: CGFloat, size: CGFloat) {
        let letters = Array(model.prefix(28)).map(String.init)
        let font = UIFont(name: ClassicTypeface.name, size: size) ?? UIFont.systemFont(ofSize: size)
        let width = letters.reduce(CGFloat.zero) { $0 + $1.size(withAttributes: [.font: font]).width }
        let fit = width > 0 ? min(1, radius * 1.0 / width) : 1
        let size = size * fit
        let fitted = font.withSize(size)
        let widths = letters.map { $0.size(withAttributes: [.font: fitted]).width }
        var offset = -widths.reduce(0, +) / 2
        for (letter, width) in zip(letters, widths) {
            let angle = Double((offset + width / 2) / radius) * 180 / .pi
            place(graphics, text: letter, size: size, at: point(center, radius, 270 + angle),
                  rotation: angle, color: ClassicDialColors.instrument)
            offset += width
        }
    }

    private func point(_ center: CGPoint, _ radius: CGFloat, _ degrees: Double) -> CGPoint {
        let angle = degrees * .pi / 180
        return CGPoint(x: center.x + radius * CGFloat(cos(angle)), y: center.y + radius * CGFloat(sin(angle)))
    }

    private func place(_ graphics: GraphicsContext, text: String, size: CGFloat, at point: CGPoint,
                       rotation: Double = 0, color: Color) {
        var context = graphics
        context.translateBy(x: point.x, y: point.y)
        context.rotate(by: .degrees(rotation))
        context.draw(Text(text).font(ClassicTypeface.font(size)).foregroundColor(color), at: .zero)
    }
}

enum ClassicDialColors {
    static let background = color(0x141A28)
    static let arc = color(0x080A0F)
    static let instrument = color(0xBDBDBD)
    static let battery = color(0x01BF50)
    static let batteryLow = color(0xFFCC00)
    static let temperature = color(0x00FFFF)
    static let dialPositive = color(0xA80909)
    static let dialNegative = color(0x209100)

    private static func color(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 255) / 255,
              green: Double((hex >> 8) & 255) / 255,
              blue: Double(hex & 255) / 255)
    }
}
