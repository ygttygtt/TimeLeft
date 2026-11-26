import Foundation

enum PanelStyle: String, Codable {
    case compact
    case large
}

struct WorkSchedule: Codable {
    struct Override: Codable {
        let day: String
        let minutes: Int
    }

    var defaultMinutes = 18 * 60 + 30
    var startMinutes: Int?
    var workdays: Set<Int> = [2, 3, 4, 5, 6]
    var todayOverride: Override?

    static func dayKey(_ date: Date, in calendar: Calendar) -> String {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", day.year!, day.month!, day.day!)
    }

    func target(on date: Date, in calendar: Calendar) -> (time: Date, minutes: Int, overridden: Bool)? {
        guard workdays.contains(calendar.component(.weekday, from: date)) else { return nil }

        let override = endOverride(on: date, in: calendar)
        let minutes = override?.minutes ?? defaultMinutes
        guard let time = Self.localTime(minutes, on: date, in: calendar) else { return nil }
        let components = calendar.dateComponents([.hour, .minute], from: time)
        return (time, components.hour! * 60 + components.minute!, override != nil)
    }

    func endOverride(on date: Date, in calendar: Calendar) -> Override? {
        todayOverride.flatMap { $0.day == Self.dayKey(date, in: calendar) ? $0 : nil }
    }

    func nextStart(after now: Date, in calendar: Calendar) -> Date? {
        guard let startMinutes, !workdays.isEmpty else { return nil }
        for offset in 0...7 {
            let day = calendar.date(byAdding: .day, value: offset, to: now)!
            if workdays.contains(calendar.component(.weekday, from: day)),
               let start = Self.localTime(startMinutes, on: day, in: calendar), start > now {
                return start
            }
        }
        return nil
    }

    static func clockTime(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    static func localTime(_ minutes: Int, on date: Date, in calendar: Calendar) -> Date? {
        guard let time = calendar.date(
            bySettingHour: minutes / 60, minute: minutes % 60, second: 0,
            of: date, matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward
        ), calendar.isDate(time, inSameDayAs: date) else { return nil }
        return time
    }
}

struct Countdown: Equatable {
    enum Phase: Equatable {
        case beforeWork
        case working
        case afterWork
        case restDay
    }

    struct NextStart: Equatable {
        let date: Date
        let seconds: Int
        let title: String

        init(date: Date, now: Date, calendar: Calendar) {
            self.date = date
            seconds = max(0, Int(ceil(date.timeIntervalSince(now))))
            let components = calendar.dateComponents([.weekday, .hour, .minute], from: date)
            let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
            let day = if calendar.isDate(date, inSameDayAs: now) {
                "今天"
            } else if calendar.isDate(date, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: now)!) {
                "明天"
            } else {
                weekdays[components.weekday! - 1]
            }
            title = "\(day) \(WorkSchedule.clockTime(components.hour! * 60 + components.minute!))"
        }

        var remaining: String {
            "\(Countdown.duration((seconds + 59) / 60))后"
        }
    }

    let phase: Phase
    let seconds: Int?
    let targetMinutes: Int?
    let overridden: Bool
    let hasStartTime: Bool
    let nextStart: NextStart?
    let elapsedMinutes: Int?

    init(schedule: WorkSchedule, now: Date, calendar: Calendar) {
        let target = schedule.target(on: now, in: calendar)
        let start = schedule.startMinutes.flatMap { WorkSchedule.localTime($0, on: now, in: calendar) }
        hasStartTime = schedule.startMinutes != nil
        targetMinutes = target?.minutes
        overridden = target?.overridden ?? false

        if let target {
            if let start, now < start, now < target.time {
                phase = .beforeWork
                seconds = nil
                elapsedMinutes = nil
            } else if now < target.time {
                phase = .working
                seconds = Int(ceil(target.time.timeIntervalSince(now)))
                elapsedMinutes = nil
            } else {
                phase = .afterWork
                seconds = 0
                elapsedMinutes = Int(now.timeIntervalSince(target.time) / 60)
            }
        } else {
            phase = .restDay
            seconds = nil
            elapsedMinutes = nil
        }
        nextStart = phase == .working ? nil : schedule.nextStart(after: now, in: calendar)
            .map { NextStart(date: $0, now: now, calendar: calendar) }
    }

    var menuTitle: String? {
        switch phase {
        case .beforeWork: "未上班"
        case .working: seconds.map(Self.digital)
        case .afterWork: "已下班"
        case .restDay: hasStartTime ? "休息中" : nil
        }
    }

    var targetTitle: String? {
        targetMinutes.map(WorkSchedule.clockTime)
    }

    var afterWorkTitle: String {
        if let elapsedMinutes, elapsedMinutes > 0 {
            return "已下班 \(Self.duration(elapsedMinutes))"
        }
        return "已下班"
    }

    static func digital(_ seconds: Int) -> String {
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }

    private static func duration(_ minutes: Int) -> String {
        let days = minutes / 1440
        let hours = minutes / 60 % 24
        let remainder = minutes % 60
        if days > 0 {
            return hours > 0 ? "\(days) 天 \(hours) 小时" : "\(days) 天"
        }
        if hours > 0 {
            return remainder > 0 ? "\(hours) 小时 \(remainder) 分" : "\(hours) 小时"
        }
        return "\(minutes) 分钟"
    }
}
