//
//  WeekGridView.swift
//  Créneau
//
//  The whole week at a glance: one column per day, blocked ranges filled in.
//
//  A flat list of rules never answered the question you actually have — "what
//  does my Tuesday look like?" — because a rule spans several days and a day is
//  covered by several rules. The grid inverts that: days are the axis, rules are
//  what fills them.
//

import SwiftUI

struct WeekGridView: View {
    let rules: [ScheduleRule]
    let activeRuleIDs: Set<UUID>
    let onSelectRule: (ScheduleRule) -> Void
    let onSelectDay: (Int) -> Void

    /// Height of the 24-hour axis. Enough to read, short enough to sit above
    /// the rule list without scrolling.
    private let gridHeight: CGFloat = 260
    private let hourLabelWidth: CGFloat = 30
    private let markedHours = [0, 6, 12, 18, 24]

    var body: some View {
        VStack(spacing: 6) {
            dayHeader
            grid
            legend
        }
    }

    // MARK: - Header

    private var dayHeader: some View {
        HStack(spacing: 2) {
            Color.clear.frame(width: hourLabelWidth)
            ForEach(ScheduleRule.orderedWeekdays, id: \.self) { day in
                Text(String(ScheduleRule.shortName(day).prefix(1)))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isWeekend(day) ? Color.amber : .secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Grid

    private var grid: some View {
        GeometryReader { geo in
            let columnWidth = (geo.size.width - hourLabelWidth) / 7
            ZStack(alignment: .topLeading) {
                hourLines(width: geo.size.width)

                ForEach(Array(ScheduleRule.orderedWeekdays.enumerated()), id: \.element) { index, day in
                    dayColumn(day: day, index: index, width: columnWidth)
                }
            }
        }
        .frame(height: gridHeight)
    }

    private func hourLines(width: CGFloat) -> some View {
        ForEach(markedHours, id: \.self) { hour in
            let y = gridHeight * CGFloat(hour) / 24
            Group {
                Path { path in
                    path.move(to: CGPoint(x: hourLabelWidth, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)

                Text("\(hour)h")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .frame(width: hourLabelWidth, alignment: .leading)
                    .offset(y: y - 6)
            }
        }
    }

    private func dayColumn(day: Int, index: Int, width: CGFloat) -> some View {
        let x = hourLabelWidth + CGFloat(index) * width

        return ZStack(alignment: .topLeading) {
            // Empty background — tapping it creates a rule on that day.
            Rectangle()
                .fill(isWeekend(day) ? Color.secondary.opacity(0.06) : Color.secondary.opacity(0.03))
                .frame(width: width - 2, height: gridHeight)
                .contentShape(Rectangle())
                .onTapGesture { onSelectDay(day) }

            ForEach(blocks(for: day), id: \.id) { block in
                let top = gridHeight * CGFloat(block.startMinutes) / 1440
                let height = max(3, gridHeight * CGFloat(block.endMinutes - block.startMinutes) / 1440)

                RoundedRectangle(cornerRadius: 2)
                    .fill(color(for: block.ruleIndex))
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(Color.white.opacity(activeRuleIDs.contains(block.ruleID) ? 0.9 : 0), lineWidth: 1)
                    )
                    .frame(width: width - 2, height: height)
                    .offset(y: top)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let rule = rules.first(where: { $0.id == block.ruleID }) {
                            onSelectRule(rule)
                        }
                    }
            }
        }
        .frame(width: width, height: gridHeight, alignment: .topLeading)
        .offset(x: x)
    }

    // MARK: - Legend

    private var legend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(enabledRules.enumerated()), id: \.element.id) { index, rule in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color(for: index))
                            .frame(width: 9, height: 9)
                        Text(rule.name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    // MARK: - Layout maths

    private var enabledRules: [ScheduleRule] {
        rules.filter(\.isEnabled)
    }

    private struct Block {
        let id = UUID()
        let ruleID: UUID
        let ruleIndex: Int
        let startMinutes: Int
        let endMinutes: Int
    }

    /// Ranges drawn on `day`'s column, midnight-crossing rules included: their
    /// tail is drawn on the following day, matching what isActive() decides.
    private func blocks(for day: Int) -> [Block] {
        var result: [Block] = []

        for (index, rule) in enabledRules.enumerated() {
            if rule.weekdays.contains(day) {
                if rule.crossesMidnight {
                    result.append(Block(ruleID: rule.id, ruleIndex: index,
                                        startMinutes: rule.startMinutes, endMinutes: 1440))
                } else {
                    result.append(Block(ruleID: rule.id, ruleIndex: index,
                                        startMinutes: rule.startMinutes, endMinutes: rule.endMinutes))
                }
            }

            // Tail inherited from the previous day.
            let previous = day == 1 ? 7 : day - 1
            if rule.crossesMidnight, rule.weekdays.contains(previous), rule.endMinutes > 0 {
                result.append(Block(ruleID: rule.id, ruleIndex: index,
                                    startMinutes: 0, endMinutes: rule.endMinutes))
            }
        }

        return result
    }

    private func isWeekend(_ day: Int) -> Bool {
        day == 1 || day == 7
    }

    /// Warm tones only, so several rules stay distinguishable without turning
    /// the grid into a rainbow.
    private func color(for index: Int) -> Color {
        let palette: [Color] = [
            Color.amber,
            Color(red: 0.788, green: 0.365, blue: 0.098),
            Color(red: 0.855, green: 0.518, blue: 0.290),
        ]
        return palette[index % palette.count].opacity(0.85)
    }
}
