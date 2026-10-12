import AppKit

enum ContrastFailure: Error {
    case belowMinimum(String, Double)
}

@main
enum ContrastSmoke {
    static func main() throws {
        let appearances: [(String, NSAppearance)] = [
            ("Light", NSAppearance(named: .aqua)!),
            ("Dark", NSAppearance(named: .darkAqua)!)
        ]

        for (name, appearance) in appearances {
            let editor = contrast(
                foreground: .labelColor,
                opacity: 0.98,
                background: .textBackgroundColor,
                appearance: appearance
            )
            let settings = contrast(
                foreground: .labelColor,
                opacity: 0.98,
                background: .windowBackgroundColor,
                appearance: appearance
            )
            guard editor >= 4.5 else {
                throw ContrastFailure.belowMinimum("\(name) editor secondary text", editor)
            }
            guard settings >= 4.5 else {
                throw ContrastFailure.belowMinimum("\(name) settings secondary text", settings)
            }
            print("\(name): editor \(format(editor)):1, settings \(format(settings)):1")
        }

        let glassSamples: [(String, NSAppearance, NSColor)] = [
            ("Light glass", appearances[0].1, NSColor(srgbRed: 0.9, green: 0.9, blue: 0.9, alpha: 1)),
            ("Dark glass", appearances[1].1, NSColor(srgbRed: 0.4, green: 0.4, blue: 0.4, alpha: 1))
        ]
        for (name, appearance, background) in glassSamples {
            let ratio = contrast(
                foreground: .labelColor,
                opacity: 0.98,
                background: background,
                appearance: appearance
            )
            guard ratio >= 4.5 else {
                throw ContrastFailure.belowMinimum("\(name) secondary text", ratio)
            }
            print("\(name): secondary text \(format(ratio)):1")
        }

        let accents: [(String, NSColor)] = [
            ("Blue", .systemBlue),
            ("Purple", .systemPurple),
            ("Green", .systemGreen),
            ("Orange", .systemOrange),
            ("Pink", .systemPink),
            ("Neutral", .systemGray)
        ]
        for (appearanceName, appearance) in appearances {
            for (accentName, accent) in accents {
                let checkmark = contrast(
                    foreground: .black,
                    opacity: 1,
                    background: accent,
                    appearance: appearance
                )
                guard checkmark >= 3 else {
                    throw ContrastFailure.belowMinimum(
                        "\(appearanceName) \(accentName) accent checkmark",
                        checkmark
                    )
                }
            }
        }
        print("Text contrast passed WCAG AA")
        print("Accent checkmarks passed non-text contrast")
    }

    private static func resolved(
        _ color: NSColor,
        appearance: NSAppearance
    ) -> (red: Double, green: Double, blue: Double, alpha: Double) {
        var result = (0.0, 0.0, 0.0, 0.0)
        appearance.performAsCurrentDrawingAppearance {
            let converted = color.usingColorSpace(.sRGB)!
            result = (
                Double(converted.redComponent),
                Double(converted.greenComponent),
                Double(converted.blueComponent),
                Double(converted.alphaComponent)
            )
        }
        return result
    }

    private static func contrast(
        foreground: NSColor,
        opacity: Double,
        background: NSColor,
        appearance: NSAppearance
    ) -> Double {
        let foreground = resolved(foreground, appearance: appearance)
        let background = resolved(background, appearance: appearance)
        let alpha = foreground.alpha * opacity
        let red = foreground.red * alpha + background.red * (1 - alpha)
        let green = foreground.green * alpha + background.green * (1 - alpha)
        let blue = foreground.blue * alpha + background.blue * (1 - alpha)
        let foregroundLuminance = luminance(red, green, blue)
        let backgroundLuminance = luminance(background.red, background.green, background.blue)
        return (max(foregroundLuminance, backgroundLuminance) + 0.05)
            / (min(foregroundLuminance, backgroundLuminance) + 0.05)
    }

    private static func luminance(_ red: Double, _ green: Double, _ blue: Double) -> Double {
        func linear(_ value: Double) -> Double {
            value <= 0.04045
                ? value / 12.92
                : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
