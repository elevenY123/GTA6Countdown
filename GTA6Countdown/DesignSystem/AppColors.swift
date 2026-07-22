import SwiftUI
import UIKit

enum AppColors {
    static let background = dynamic(
        light: UIColor(red: 0.97, green: 0.94, blue: 0.98, alpha: 1),
        dark: UIColor(red: 0.035, green: 0.045, blue: 0.12, alpha: 1)
    )

    static let surface = dynamic(
        light: UIColor(red: 1, green: 0.98, blue: 1, alpha: 0.88),
        dark: UIColor(red: 0.09, green: 0.08, blue: 0.20, alpha: 0.88)
    )

    static let primary = dynamic(
        light: UIColor(red: 0.72, green: 0.12, blue: 0.48, alpha: 1),
        dark: UIColor(red: 1, green: 0.25, blue: 0.68, alpha: 1)
    )

    static let secondary = dynamic(
        light: UIColor(red: 0.93, green: 0.28, blue: 0.36, alpha: 1),
        dark: UIColor(red: 0.28, green: 0.82, blue: 0.95, alpha: 1)
    )

    static let accent = dynamic(
        light: UIColor(red: 0.50, green: 0.19, blue: 0.70, alpha: 1),
        dark: UIColor(red: 0.72, green: 0.36, blue: 1, alpha: 1)
    )

    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}
