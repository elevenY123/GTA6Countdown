import SwiftUI

enum AppTypography {
    static let hero = Font.system(.largeTitle, design: .rounded).weight(.black)
    static let title = Font.system(.title2, design: .rounded).weight(.bold)
    static let headline = Font.system(.headline, design: .rounded).weight(.semibold)
    static let body = Font.system(.body, design: .default)
    static let metadata = Font.system(.caption, design: .rounded).weight(.medium)
}
