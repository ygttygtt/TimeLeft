import Foundation
import UserNotifications

@MainActor
final class Reminders: NSObject, UNUserNotificationCenterDelegate {
    private struct Ledger: Codable {
        var scheduled: [String: Date] = [:]
        var elapsed: Set<String> = []
    }

    private let center = UNUserNotificationCenter.current()
    private let defaults: UserDefaults
    private let ledgerKey = "reminderLedger"
    private let requestPrefix = "timeleft.end."
    private var ledger: Ledger

    init(defaults: UserDefaults) {
        self.defaults = defaults
        ledger = defaults.data(forKey: ledgerKey)
            .flatMap { try? JSONDecoder().decode(Ledger.self, from: $0) } ?? Ledger()
        super.init()
        center.delegate = self
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func authorize() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func synchronize(
        enabled: Bool, schedule: WorkSchedule, now: Date, calendar: Calendar
    ) async throws -> Bool {
        ledger.elapsed.formUnion(ledger.scheduled.filter { $0.value <= now }.keys)
        // Persist a partial schedule too, so a later retry retains each successful request.
        defer { defaults.set(try? JSONEncoder().encode(ledger), forKey: ledgerKey) }
        guard enabled else {
            center.removeAllPendingNotificationRequests()
            ledger.scheduled.removeAll()
            return false
        }

        let authorized = await center.notificationSettings().authorizationStatus == .authorized
        let delivered = await center.deliveredNotifications()
        ledger.elapsed.formUnion(delivered.compactMap { day(for: $0.request.identifier) })

        var desired: [String: Date] = [:]
        if authorized {
            // Keep the coming workweek scheduled even if the Mac sleeps overnight.
            for offset in 0...7 {
                let date = calendar.date(byAdding: .day, value: offset, to: now)!
                let day = WorkSchedule.dayKey(date, in: calendar)
                if let target = schedule.target(on: date, in: calendar),
                   target.time > now, !ledger.elapsed.contains(day) {
                    desired[day] = target.time
                }
            }
        }

        let pending = await center.pendingNotificationRequests()
        let obsolete = pending.compactMap { request -> String? in
            guard let day = day(for: request.identifier), desired[day] == nil else { return nil }
            return request.identifier
        }
        center.removePendingNotificationRequests(withIdentifiers: obsolete)
        ledger.scheduled = ledger.scheduled.filter { desired[$0.key] != nil }

        for (day, target) in desired.sorted(by: { $0.value < $1.value }) {
            let identifier = requestPrefix + day
            if ledger.scheduled[day] == target,
               pending.contains(where: { $0.identifier == identifier }) {
                continue
            }
            let content = UNMutableNotificationContent()
            content.title = "已下班"
            content.body = "到设定的下班时间了。"
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents(
                    [.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second], from: target
                ),
                repeats: false
            )
            try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            ledger.scheduled[day] = target
        }
        return authorized
    }

    private func day(for identifier: String) -> String? {
        guard identifier.hasPrefix(requestPrefix) else { return nil }
        return String(identifier.dropFirst(requestPrefix.count))
    }
}
