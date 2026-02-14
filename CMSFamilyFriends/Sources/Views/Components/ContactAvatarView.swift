import SwiftUI

/// Wiederverwendbarer Kontakt-Avatar mit Profilbild oder Initialen
struct ContactAvatarView: View {
    let contact: TrackedContact
    var size: CGFloat = 40
    
    var body: some View {
        ZStack {
            Circle()
                .fill(avatarColor)
                .frame(width: size, height: size)
            
            if let imageData = contact.profileImageData,
               let nsImage = NSImage(data: imageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
                    .frame(width: size, height: size)
            } else {
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .accessibilityHidden(true)
    }
    
    private var initials: String {
        let first = contact.firstName.prefix(1)
        let last = contact.lastName.prefix(1)
        return "\(first)\(last)".uppercased()
    }
    
    private var avatarColor: Color {
        let level = contact.urgencyLevel
        switch level {
        case 0..<0.5: return .blue
        case 0.5..<0.75: return .yellow
        case 0.75..<1.0: return .orange
        default: return .red
        }
    }
}
