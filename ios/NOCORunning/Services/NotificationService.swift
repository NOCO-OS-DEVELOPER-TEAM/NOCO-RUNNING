import UserNotifications

@MainActor
final class NotificationService {
    func request() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }
}
