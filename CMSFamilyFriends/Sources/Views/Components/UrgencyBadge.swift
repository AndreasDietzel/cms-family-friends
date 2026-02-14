import SwiftUI

/// Wiederverwendbares Dringlichkeits-Badge
struct UrgencyBadge: View {
    let level: Double
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            
            if level >= 0.75 {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(color)
                    .fontWeight(.medium)
            }
        }
        .padding(.horizontal, level >= 0.75 ? 8 : 0)
        .padding(.vertical, 2)
        .background(level >= 0.75 ? color.opacity(0.1) : .clear)
        .clipShape(Capsule())
        .accessibilityLabel("Dringlichkeit: \(label)")
    }
    
    private var color: Color {
        switch level {
        case 0..<0.5: return .green
        case 0.5..<0.75: return .yellow
        case 0.75..<1.0: return .orange
        default: return .red
        }
    }
    
    private var label: String {
        switch level {
        case 0..<0.5: return "Aktuell"
        case 0.5..<0.75: return "Bald fällig"
        case 0.75..<1.0: return "Dringend"
        default: return "Überfällig"
        }
    }
}
