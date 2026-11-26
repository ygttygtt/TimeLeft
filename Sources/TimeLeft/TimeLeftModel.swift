import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class TimeLeftModel: ObservableObject {
    struct Preferences: Codable {
        var schedule = WorkSchedule()
        var panelStyle = PanelStyle.compact
        var remindersEnabled = false
    }

    @Published private(set) var preferences: Preferences
    @Published private(set) var countdown: Countdown
    @Published private(set) var changingReminder = false
    @Published private(set) var reminderProblem: String?
    @Published private(set) var loginStatus = SMAppService.mainApp.status
    @Published private(set) var loginProblem: String?

    private let defaults: UserDefaults
    private let reminders: Reminders
    private let preferencesKey = "preferences"
    private var timer: Timer?
    private var panelVisible = false
    private var currentDay: String
    private var reminderSync: Task<Void, Never>?
    private var reminderSyncNeeded = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reminders = Reminders(defaults: defaults)
        let preferences = defaults.data(forKey: preferencesKey)
            .flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? Preferences()
        self.preferences = preferences
        let now = Date()
        let calendar = Self.localCalendar
        currentDay = WorkSchedule.dayKey(now, in: calendar)
        countdown = Countdown(schedule: preferences.schedule, now: now, calendar: calendar)

        observeClockChanges()
        refreshClock(syncReminders: true)
    }

    func setPanelStyle(_ style: PanelStyle) {
        preferences.panelStyle = style
        savePreferences()
    }

    func setDefaultTime(_ minutes: Int) -> Bool {
        guard isValidEndTime(minutes) else { return false }
        preferences.schedule.defaultMinutes = minutes
        saveSchedule()
        return true
    }

    var startTimeLimit: Int {
        let schedule = preferences.schedule
        let today = schedule.endOverride(on: Date(), in: Self.localCalendar)?.minutes
        return min(schedule.defaultMinutes, today ?? schedule.defaultMinutes)
    }

    func setStartTime(_ minutes: Int?) -> Bool {
        if let minutes, minutes >= startTimeLimit { return false }
        preferences.schedule.startMinutes = minutes
        saveSchedule()
        return true
    }

    func isValidEndTime(_ minutes: Int) -> Bool {
        preferences.schedule.startMinutes.map { minutes > $0 } ?? true
    }

    func setWorkday(_ weekday: Int, selected: Bool) {
        if selected {
            preferences.schedule.workdays.insert(weekday)
        } else {
            preferences.schedule.workdays.remove(weekday)
        }
        saveSchedule()
    }

    func setTodayTime(_ minutes: Int) -> Bool {
        guard isValidEndTime(minutes) else { return false }
        let day = WorkSchedule.dayKey(Date(), in: Self.localCalendar)
        preferences.schedule.todayOverride = .init(day: day, minutes: minutes)
        saveSchedule()
        return true
    }

    func clearTodayTime() {
        preferences.schedule.todayOverride = nil
        saveSchedule()
    }

    func setReminders(_ enabled: Bool) {
        reminderProblem = nil
        if !enabled {
            preferences.remindersEnabled = false
            saveSchedule()
            return
        }

        changingReminder = true
        Task {
            defer { changingReminder = false }
            do {
                let authorized = try await reminders.authorize()
                preferences.remindersEnabled = authorized
                saveSchedule()
                if !authorized { reminderProblem = "请在系统设置的「通知」中允许 TimeLeft。" }
            } catch {
                reminderProblem = "无法开启下班提醒：\(error.localizedDescription)"
            }
        }
    }

    var loginItemEnabled: Bool {
        loginStatus == .enabled || loginStatus == .requiresApproval
    }

    func updateLoginStatus() {
        loginStatus = SMAppService.mainApp.status
    }

    func setLoginItem(_ enabled: Bool) {
        loginProblem = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginProblem = "无法更改登录项：\(error.localizedDescription)"
        }
        updateLoginStatus()
    }

    func openLoginItemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func quit() {
        Task {
            await reminderSync?.value
            NSApplication.shared.terminate(nil)
        }
    }

    func setPanelVisible(_ visible: Bool) {
        panelVisible = visible
        refreshClock()
    }

    private static var localCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private func savePreferences() {
        defaults.set(try? JSONEncoder().encode(preferences), forKey: preferencesKey)
    }

    private func saveSchedule() {
        savePreferences()
        refreshClock(syncReminders: true)
    }

    private func observeClockChanges() {
        let center = NotificationCenter.default
        for name in [Notification.Name.NSCalendarDayChanged, .NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshClock(syncReminders: true) }
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshClock(syncReminders: true) }
        }
    }

    private func refreshClock(syncReminders: Bool = false) {
        let now = Date()
        let calendar = Self.localCalendar
        let day = WorkSchedule.dayKey(now, in: calendar)
        let updated = Countdown(schedule: preferences.schedule, now: now, calendar: calendar)
        let reachedEnd = countdown.phase != .afterWork && updated.phase == .afterWork
        let changedDay = currentDay != day
        currentDay = day

        if syncReminders || countdown != updated { countdown = updated }
        if syncReminders || reachedEnd || changedDay { synchronizeReminders() }

        let nextMidnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let nextRefresh: Date
        if updated.phase == .working || (panelVisible && updated.phase == .beforeWork) {
            nextRefresh = Date(timeIntervalSinceReferenceDate: floor(now.timeIntervalSinceReferenceDate) + 1)
        } else if updated.phase == .beforeWork, let start = updated.nextStart {
            nextRefresh = min(nextMidnight, start.date)
        } else if panelVisible {
            let seconds = now.timeIntervalSinceReferenceDate
            let nextMinute = Date(timeIntervalSinceReferenceDate: (floor(seconds / 60) + 1) * 60)
            nextRefresh = min(nextMidnight, nextMinute)
        } else {
            nextRefresh = nextMidnight
        }

        timer?.invalidate()
        let timer = Timer(fire: nextRefresh, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.refreshClock() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func synchronizeReminders() {
        reminderSyncNeeded = true
        guard reminderSync == nil else { return }
        reminderSync = Task {
            while reminderSyncNeeded {
                reminderSyncNeeded = false
                let preferences = preferences
                do {
                    let authorized = try await reminders.synchronize(
                        enabled: preferences.remindersEnabled, schedule: preferences.schedule,
                        now: Date(), calendar: Self.localCalendar
                    )
                    if self.preferences.remindersEnabled {
                        reminderProblem = authorized ? nil : "请在系统设置的「通知」中允许 TimeLeft。"
                    }
                } catch {
                    reminderProblem = "无法安排下班提醒：\(error.localizedDescription)"
                }
            }
            reminderSync = nil
        }
    }
}
