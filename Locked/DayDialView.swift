//
//  DayDialView.swift
//  Créneau
//
//  The hero: today as a 24-hour dial, blocked ranges filled in amber, a hand at
//  the current time, and at the centre what matters — blocked or free, and how
//  long until that changes.
//
//  Deliberately not a padlock. A padlock says "locked / unlocked"; a dial says
//  "your day has shape and you are somewhere in it", which is what this app is
//  actually about.
//

import SwiftUI

struct DayDialView: View {
    let groups: [BlockGroup]
    let activeGroupIDs: Set<UUID>
    let now: Date
    let nextEvent: ScheduleStore.NextEvent?

    /// One ring per group, drawn from the outside in. Overlaying them on a
    /// single ring hid whichever group was drawn first — and with a work group
    /// and a leisure group, that is most of the day.
    private let ringWidth: CGFloat = 14
    private let ringGap: CGFloat = 4

    var body: some View {
        ZStack {
            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                let outerRadius = (size - ringWidth) / 2
                let centre = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

                Canvas { context, _ in
                    for (index, group) in enabledGroups.enumerated() {
                        let radius = outerRadius - CGFloat(index) * (ringWidth + ringGap)
                        guard radius > ringWidth else { break }
                        drawTrack(in: context, centre: centre, radius: radius)
                        drawBlocks(for: group, index: index, in: context,
                                   centre: centre, radius: radius)
                    }
                    if enabledGroups.isEmpty {
                        drawTrack(in: context, centre: centre, radius: outerRadius)
                    }
                    drawTicks(in: context, centre: centre, radius: outerRadius)
                    drawHand(in: context, centre: centre, radius: outerRadius)
                }
            }
            centreLabel
        }
        .frame(height: 260)
    }

    // MARK: - Drawing

    /// 0h at the top, clockwise, like any clock face.
    private func angle(forMinutes minutes: Int) -> Angle {
        .degrees(Double(minutes) / 1440 * 360 - 90)
    }

    private func drawTrack(in context: GraphicsContext, centre: CGPoint, radius: CGFloat) {
        var path = Path()
        path.addArc(center: centre, radius: radius, startAngle: .degrees(0),
                    endAngle: .degrees(360), clockwise: false)
        context.stroke(path, with: .color(Color.dialTrack), lineWidth: ringWidth)
    }

    private func drawBlocks(for group: BlockGroup, index: Int, in context: GraphicsContext,
                            centre: CGPoint, radius: CGFloat) {
        let isActive = activeGroupIDs.contains(group.id)
        for block in todaysBlocks(of: group) {
            var path = Path()
            path.addArc(
                center: centre,
                radius: radius,
                startAngle: angle(forMinutes: block.start),
                endAngle: angle(forMinutes: block.end),
                clockwise: false
            )
            context.stroke(
                path,
                with: .color(color(for: index).opacity(isActive ? 1 : 0.5)),
                style: StrokeStyle(lineWidth: ringWidth, lineCap: .butt)
            )
        }
    }

    private func drawTicks(in context: GraphicsContext, centre: CGPoint, radius: CGFloat) {
        for hour in stride(from: 0, to: 24, by: 3) {
            let a = CGFloat(angle(forMinutes: hour * 60).radians)
            let inner = radius - ringWidth / 2 - 6
            let outer = radius - ringWidth / 2 - 1
            var path = Path()
            path.move(to: CGPoint(x: centre.x + cos(a) * inner, y: centre.y + sin(a) * inner))
            path.addLine(to: CGPoint(x: centre.x + cos(a) * outer, y: centre.y + sin(a) * outer))
            context.stroke(path, with: .color(Color.dialTick), lineWidth: hour % 6 == 0 ? 2 : 1)

            if hour % 6 == 0 {
                let labelRadius = radius - ringWidth / 2 - 18
                let point = CGPoint(x: centre.x + cos(a) * labelRadius,
                                    y: centre.y + sin(a) * labelRadius)
                context.draw(
                    Text("\(hour)").font(.system(size: 10, weight: .medium)).foregroundColor(Color.dialTick),
                    at: point
                )
            }
        }
    }

    private func drawHand(in context: GraphicsContext, centre: CGPoint, radius: CGFloat) {
        let a = CGFloat(angle(forMinutes: currentMinutes).radians)
        let outer = radius + ringWidth / 2 + 5
        let depth = CGFloat(max(enabledGroups.count, 1)) * (ringWidth + ringGap)
        let inner = max(radius - depth, radius * 0.35)

        var path = Path()
        path.move(to: CGPoint(x: centre.x + cos(a) * inner, y: centre.y + sin(a) * inner))
        path.addLine(to: CGPoint(x: centre.x + cos(a) * outer, y: centre.y + sin(a) * outer))
        context.stroke(path, with: .color(Color.dialHand),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round))

        let dot = CGRect(x: centre.x + cos(a) * outer - 4, y: centre.y + sin(a) * outer - 4,
                         width: 8, height: 8)
        context.fill(Path(ellipseIn: dot), with: .color(Color.dialHand))
    }

    // MARK: - Centre

    private var centreLabel: some View {
        VStack(spacing: 4) {
            Text(isBlocked ? "Bloqué" : "Libre")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(isBlocked ? Color.amber : Color.freeState)

            if isBlocked && !activeNames.isEmpty {
                Text(activeNames)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.amber.opacity(0.8))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }

            if let event = nextEvent {
                Text("\(event.groupName) \(event.isOpening ? "s'ouvre" : "se ferme") dans \(durationLabel(event.minutes))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
            } else {
                Text(groups.isEmpty ? "Aucun groupe" : "Rien ne change aujourd'hui")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 150)
        .multilineTextAlignment(.center)
    }

    private func durationLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m)"
    }

    private var isBlocked: Bool { !activeGroupIDs.isEmpty }

    private var activeNames: String {
        groups.filter { activeGroupIDs.contains($0.id) }.map(\.name).joined(separator: ", ")
    }

    private var currentMinutes: Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: now)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    // MARK: - Today's ranges

    private struct DialBlock {
        let start: Int
        let end: Int
    }

    private var enabledGroups: [BlockGroup] {
        groups.filter(\.isEnabled)
    }

    /// Ranges covering today for one group, tails of yesterday's
    /// midnight-crossing windows included — the dial shows the day as it is
    /// lived, not as it is stored.
    private func todaysBlocks(of group: BlockGroup) -> [DialBlock] {
        let weekday = Calendar.current.component(.weekday, from: now)
        let previous = weekday == 1 ? 7 : weekday - 1
        var result: [DialBlock] = []

        for window in group.windows {
            if window.weekdays.contains(weekday) {
                result.append(DialBlock(
                    start: window.startMinutes,
                    end: window.crossesMidnight ? 1440 : window.endMinutes
                ))
            }
            if window.crossesMidnight, window.weekdays.contains(previous), window.endMinutes > 0 {
                result.append(DialBlock(start: 0, end: window.endMinutes))
            }
        }
        return result
    }

    private func color(for index: Int) -> Color {
        let palette: [Color] = [
            Color.amber,
            Color(red: 0.788, green: 0.365, blue: 0.098),
            Color(red: 0.855, green: 0.518, blue: 0.290),
        ]
        return palette[index % palette.count]
    }
}
