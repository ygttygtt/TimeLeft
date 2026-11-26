import AppKit
import SwiftUI

struct TimeLeftPanel: View {
    enum Page {
        case home
        case settings
        case editToday
        case editStart
        case editDefaultEnd

        var depth: Int {
            switch self {
            case .home: 0
            case .settings, .editToday: 1
            case .editStart, .editDefaultEnd: 2
            }
        }
    }

    final class Navigation: ObservableObject {
        @Published var todayMinutes = 0
        @Published var startMinutes = 0
        @Published var defaultEndMinutes = 0
        let show: (Page) -> Void

        init(show: @escaping (Page) -> Void) {
            self.show = show
        }
    }

    private struct Layout: Equatable {
        let style: PanelStyle
        let hasTarget: Bool
        let phase: Countdown.Phase
        let hasNextStart: Bool
        let overridden: Bool
        let hasStartTime: Bool
        let invalidEdit: Bool
        let reminderProblem: String?
        let loginProblem: String?
        let loginNeedsApproval: Bool
    }

    @ObservedObject var model: TimeLeftModel
    let page: Page
    @ObservedObject var navigation: Navigation
    let onLayoutChange: () -> Void
    static let width: CGFloat = 288

    var body: some View {
        VStack(spacing: 0) {
            switch page {
            case .home:
                home
            case .settings:
                settings
            case .editToday:
                editToday
            case .editStart, .editDefaultEnd:
                editScheduleTime
            }
        }
        .frame(width: Self.width)
        .fixedSize()
        .onChange(of: layout) { _ in onLayoutChange() }
    }

    private var layout: Layout {
        Layout(
            style: model.preferences.panelStyle,
            hasTarget: model.countdown.targetMinutes != nil,
            phase: model.countdown.phase, hasNextStart: model.countdown.nextStart != nil,
            overridden: model.countdown.overridden, hasStartTime: model.preferences.schedule.startMinutes != nil,
            invalidEdit: invalidEdit,
            reminderProblem: model.reminderProblem, loginProblem: model.loginProblem,
            loginNeedsApproval: model.loginStatus == .requiresApproval
        )
    }

    private var invalidEdit: Bool {
        switch page {
        case .home, .settings: false
        case .editToday: !model.isValidEndTime(navigation.todayMinutes)
        case .editStart: navigation.startMinutes >= model.startTimeLimit
        case .editDefaultEnd: !model.isValidEndTime(navigation.defaultEndMinutes)
        }
    }

    private var home: some View {
        VStack(spacing: 2) {
            summary
            Divider().padding(.horizontal, 7).padding(.vertical, 3)
            if let targetMinutes = model.countdown.targetMinutes {
                menuButton("仅改今天…", navigates: true) {
                    navigation.todayMinutes = targetMinutes
                    navigation.show(.editToday)
                }
                if model.countdown.overridden {
                    menuButton("恢复默认时间", action: model.clearTodayTime)
                }
            }
            menuButton("设置…", navigates: true) { navigation.show(.settings) }
                .keyboardShortcut(",", modifiers: .command)
            Divider().padding(.horizontal, 7).padding(.vertical, 3)
            menuButton("退出 TimeLeft", secondary: true, action: model.quit)
        }
        .padding(8)
    }

    @ViewBuilder
    private var summary: some View {
        let large = model.preferences.panelStyle == .large
        switch model.countdown.phase {
        case .beforeWork:
            if let start = model.countdown.nextStart {
                if large {
                    largeCountdown("距离上班还有", seconds: start.seconds, time: start.title)
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        settingsRow("即将上班") {
                            Text(start.title).monospacedDigit().fontWeight(.semibold)
                        }
                        Text("距离上班 \(Countdown.digital(start.seconds))")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                }
            }
        case .working:
            if large, let seconds = model.countdown.seconds, let target = model.countdown.targetTitle {
                largeCountdown("距离下班还有", seconds: seconds, time: "今天 \(target)")
            } else {
                compactSummary
            }
        case .afterWork, .restDay:
            restSummary(large: large)
        }
    }

    private var compactSummary: some View {
        HStack {
            Text("今天下班")
            Spacer(minLength: 8)
            if let target = model.countdown.targetTitle {
                Text(target).monospacedDigit().fontWeight(.semibold)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
    }

    private func largeCountdown(_ title: String, seconds: Int, time: String) -> some View {
        VStack(spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            Text(Countdown.digital(seconds))
                .font(.system(size: 32, weight: .semibold))
                .monospacedDigit()
            Text(time).foregroundStyle(.secondary).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private func restSummary(large: Bool) -> some View {
        let countdown = model.countdown
        return VStack(alignment: .leading, spacing: 7) {
            Text(countdown.phase == .afterWork ? countdown.afterWorkTitle : "今天休息")
                .font(large ? .title2.weight(.semibold) : .body.weight(.semibold))
                .monospacedDigit()
            if let start = countdown.nextStart {
                Divider()
                settingsRow("下次上班") {
                    Text(start.title).monospacedDigit().fontWeight(.semibold)
                }
                Text(start.remaining).foregroundStyle(.secondary).monospacedDigit()
            } else if let target = countdown.targetTitle {
                Text("今天 \(target)").foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, large ? 10 : 7)
    }

    private var settings: some View {
        VStack(spacing: 9) {
            header("设置")
            settingGroup {
                let schedule = model.preferences.schedule
                timeSetting("上班时间", value: schedule.startMinutes.map(WorkSchedule.clockTime) ?? "未设置") {
                    navigation.startMinutes = schedule.startMinutes ?? max(0, min(9 * 60, model.startTimeLimit - 1))
                    navigation.show(.editStart)
                }
                Divider()
                timeSetting("默认下班时间", value: WorkSchedule.clockTime(schedule.defaultMinutes)) {
                    navigation.defaultEndMinutes = schedule.defaultMinutes
                    navigation.show(.editDefaultEnd)
                }
                Divider()
                VStack(alignment: .leading, spacing: 7) {
                    Text("工作日")
                    HStack(spacing: 4) {
                        workday("一", day: 2)
                        workday("二", day: 3)
                        workday("三", day: 4)
                        workday("四", day: 5)
                        workday("五", day: 6)
                        workday("六", day: 7)
                        workday("日", day: 1)
                    }
                }
            }
            settingGroup {
                settingsRow("面板样式") {
                    Picker("面板样式", selection: Binding(
                        get: { model.preferences.panelStyle }, set: model.setPanelStyle
                    )) {
                        Text("极简").tag(PanelStyle.compact)
                        Text("大字").tag(PanelStyle.large)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 106)
                }
            }
            settingGroup {
                switchRow("下班提醒", isOn: Binding(
                    get: { model.preferences.remindersEnabled }, set: model.setReminders
                ))
                .disabled(model.changingReminder)
                if let issue = model.reminderProblem {
                    Text(issue).font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                switchRow("登录时打开", isOn: Binding(
                    get: { model.loginItemEnabled }, set: model.setLoginItem
                ))
                if model.loginStatus == .requiresApproval {
                    Button("在系统设置中批准登录项", action: model.openLoginItemSettings)
                }
                if let issue = model.loginProblem {
                    Text(issue).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .onAppear { model.updateLoginStatus() }
    }

    private func timeSetting(_ title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            settingsRow(title) {
                HStack(spacing: 5) {
                    Text(value).monospacedDigit()
                        .frame(minWidth: 42, alignment: .trailing)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 6))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PanelButtonStyle())
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    private var editToday: some View {
        VStack(spacing: 9) {
            header("仅改今天")
            settingGroup {
                timePicker("今天下班", minutes: $navigation.todayMinutes)
                if invalidEdit {
                    Text("下班时间须晚于上班时间。").font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                settingsRow("默认下班时间") {
                    Text(WorkSchedule.clockTime(model.preferences.schedule.defaultMinutes)).monospacedDigit()
                }
                .foregroundStyle(.secondary)
            }
            editActions(backTo: .home, canSave: !invalidEdit) {
                if model.setTodayTime(navigation.todayMinutes) { navigation.show(.home) }
            }
        }
        .padding(12)
    }

    private var editScheduleTime: some View {
        let editingStart = page == .editStart
        let title = editingStart ? "上班时间" : "默认下班时间"
        let minutes = editingStart ? $navigation.startMinutes : $navigation.defaultEndMinutes
        let canClearStart = editingStart && model.preferences.schedule.startMinutes != nil
        return VStack(spacing: 9) {
            header(title, backTo: .settings)
            settingGroup {
                timePicker(title, minutes: minutes)
                if invalidEdit {
                    Text(editingStart ? "上班时间须早于当天和默认下班时间。" : "下班时间须晚于上班时间。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            editActions(backTo: .settings, canSave: !invalidEdit, canClearStart: canClearStart) {
                let saved = if editingStart {
                    model.setStartTime(minutes.wrappedValue)
                } else {
                    model.setDefaultTime(minutes.wrappedValue)
                }
                if saved { navigation.show(.settings) }
            }
        }
        .padding(12)
    }

    private func editActions(
        backTo page: Page, canSave: Bool, canClearStart: Bool = false, save: @escaping () -> Void
    ) -> some View {
        HStack {
            if canClearStart {
                Button {
                    if model.setStartTime(nil) { navigation.show(.settings) }
                } label: {
                    Text("清除上班时间")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PanelButtonStyle())
            }
            Spacer()
            Button("取消") { navigation.show(page) }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
            Button("确定", action: save)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
        }
    }

    private func header(_ title: String, backTo page: Page = .home) -> some View {
        Text(title)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .overlay(alignment: .leading) {
                backButton(to: page)
                    .accessibilityLabel("返回")
                    .help("返回")
            }
    }

    private func backButton(to page: Page) -> some View {
        Button {
            navigation.show(page)
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(nsColor: .labelColor))
                .frame(width: 27, height: 27)
                .contentShape(Rectangle())
        }
        .buttonStyle(PanelButtonStyle())
    }

    private func menuButton(
        _ title: String, navigates: Bool = false, secondary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(Color(nsColor: secondary ? .secondaryLabelColor : .labelColor))
                Spacer(minLength: 6)
                if navigates {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 27)
            .contentShape(Rectangle())
        }
        .buttonStyle(PanelButtonStyle())
    }

    private func settingGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
    }

    private func settingsRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            content()
        }
        .frame(maxWidth: .infinity)
    }

    private func switchRow(_ title: String, isOn: Binding<Bool>) -> some View {
        settingsRow(title) {
            Toggle(title, isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    private func workday(_ title: String, day: Int) -> some View {
        let selected = model.preferences.schedule.workdays.contains(day)
        return Toggle(isOn: Binding(
            get: { model.preferences.schedule.workdays.contains(day) },
            set: { model.setWorkday(day, selected: $0) }
        )) {
            Text(title)
                .foregroundStyle(selected ? Color.accentColor : .primary)
                .frame(maxWidth: .infinity)
                .frame(height: 25)
                .contentShape(Rectangle())
        }
        .toggleStyle(.button)
        .buttonStyle(PanelButtonStyle(
            resting: selected ? Color.accentColor.opacity(0.17) : Color.primary.opacity(0.055)
        ))
        .accessibilityLabel("星期\(title)")
    }

    private func timePicker(_ title: String, minutes: Binding<Int>) -> some View {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let selection = Binding<Date>(
            get: {
                // The field edits hours and minutes independently of today's DST transitions.
                calendar.date(from: DateComponents(
                    year: 2001, month: 1, day: 15, hour: minutes.wrappedValue / 60,
                    minute: minutes.wrappedValue % 60
                ))!
            },
            set: {
                minutes.wrappedValue = calendar.component(.hour, from: $0) * 60
                    + calendar.component(.minute, from: $0)
            }
        )
        return settingsRow(title) {
            TimeField(title: title, selection: selection, calendar: calendar)
                .fixedSize()
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.primary.opacity(0.055), in: Capsule())
                .overlay {
                    Capsule().strokeBorder(.primary.opacity(0.1), lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
        }
    }
}

private struct TimeField: NSViewRepresentable {
    let title: String
    @Binding var selection: Date
    let calendar: Calendar

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = .hourMinute
        picker.isBordered = false
        picker.isBezeled = false
        picker.drawsBackground = false
        picker.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        picker.locale = Locale(identifier: "zh_CN")
        picker.calendar = calendar
        picker.timeZone = calendar.timeZone
        picker.dateValue = selection
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.timeChanged(_:))
        picker.setAccessibilityLabel(title)
        return picker
    }

    func updateNSView(_ picker: NSDatePicker, context: Context) {
        let coordinator = context.coordinator
        coordinator.selection = $selection
        // AppKit applies the picker's locale when returning the calendar.
        if coordinator.calendar != calendar {
            picker.calendar = calendar
            picker.timeZone = calendar.timeZone
            coordinator.calendar = calendar
        }
        if !coordinator.matchesTime(picker.dateValue, selection) {
            picker.dateValue = selection
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection, calendar: calendar)
    }

    final class Coordinator: NSObject {
        var selection: Binding<Date>
        var calendar: Calendar

        init(selection: Binding<Date>, calendar: Calendar) {
            self.selection = selection
            self.calendar = calendar
        }

        func matchesTime(_ first: Date, _ second: Date) -> Bool {
            calendar.dateComponents([.hour, .minute], from: first)
                == calendar.dateComponents([.hour, .minute], from: second)
        }

        @objc func timeChanged(_ picker: NSDatePicker) {
            if !matchesTime(selection.wrappedValue, picker.dateValue) {
                selection.wrappedValue = picker.dateValue
            }
        }
    }
}

private struct PanelButtonStyle: ButtonStyle {
    var resting = Color.clear

    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration, resting: resting)
    }

    private struct Face: View {
        private final class Hover: ObservableObject {
            @Published var active = false
        }

        let configuration: Configuration
        let resting: Color
        @StateObject private var hover = Hover()
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(resting)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.primary.opacity(configuration.isPressed ? 0.15 : hover.active ? 0.085 : 0))
                        }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hover.active)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.09), value: configuration.isPressed)
                .onHover { hover.active = $0 }
        }
    }
}
