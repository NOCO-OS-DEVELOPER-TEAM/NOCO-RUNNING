import UIKit

enum Haptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func start() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func pause() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    static func record() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
