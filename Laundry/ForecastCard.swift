import Charts
import SwiftUI

/// For each hour of the day: the share of time at least one machine was free over the last week.
struct ForecastCard: View {
    @Environment(LaundryStore.self) private var store
    @State private var selected: Int?

    var body: some View {
        let forecast = store.forecast
        let currentHour = Calendar.current.component(.hour, from: .now)

        SectionCard(title: "各时段空闲率", footer: footer(forecast)) {
            VStack(alignment: .leading, spacing: 14) {
                Text(summary(forecast, currentHour: currentHour))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)

                Chart {
                    ForEach(0..<24, id: \.self) { h in
                        if let a = forecast.hours[h].availability {
                            hourBar(h, availability: a, isNow: h == currentHour, isSelected: h == selected)
                        }
                    }
                    if let h = selected, let a = forecast.hours[h].availability {
                        // The line stops at 100 %; the label sits on top of it, in the lane kept free
                        // above the bars, so it never spills over the text above the chart.
                        RuleMark(x: .value("时段", Double(h)),
                                 yStart: .value("空闲率", 0.0), yEnd: .value("空闲率", 1.0))
                            .foregroundStyle(Color.primary.opacity(0.35))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                            .annotation(position: .top, spacing: 3,
                                        overflowResolution: .init(x: .fit(to: .plot), y: .fit(to: .chart))) {
                                Text("\(h) 时 · \(Fmt.percent(a))")
                                    .font(.caption.weight(.semibold))
                                    .monospacedDigit()
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color(.tertiarySystemFill), in: .capsule)
                                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                            }
                    }
                }
                .chartXScale(domain: -0.5...23.5)
                .chartYScale(domain: 0...(1 + Self.labelLane))
                .chartXAxis {
                    AxisMarks(values: [0.0, 6, 12, 18, 23]) { value in
                        AxisTick()
                        AxisValueLabel {
                            if let h = value.as(Double.self) { Text("\(Int(h)) 时") }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 0.5, 1]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) { Text(Fmt.percent(v)) }
                        }
                    }
                }
                .chartXSelection(value: Binding<Double?>(
                    get: { selected.map(Double.init) },
                    set: { selected = $0.map { min(23, max(0, Int($0.rounded()))) } }
                ))
                .frame(height: 196)
                .sensoryFeedback(.selection, trigger: selected)
            }
        }
    }

    /// Headroom above 100 %, as a share of the scale: the lane for the label of the hour being touched.
    private static let labelLane = 0.22

    private func hourBar(_ h: Int, availability a: Double, isNow: Bool, isSelected: Bool) -> some ChartContent {
        let x0: Double = Double(h) - 0.36
        let x1: Double = Double(h) + 0.36
        let color: Color = isNow ? Palette.water : Palette.water.opacity(isSelected ? 0.7 : 0.35)
        return RectangleMark(xStart: .value("时段", x0), xEnd: .value("时段", x1),
                             yStart: .value("空闲率", 0.0), yEnd: .value("空闲率", a))
            .foregroundStyle(color)
            .cornerRadius(2)
            .accessibilityLabel("\(h) 时")
            .accessibilityValue("空闲率 \(Fmt.percent(a))")
    }

    private func summary(_ forecast: Forecast, currentHour: Int) -> String {
        guard forecast.hasAny else { return "数据收集中，暂无足够记录。" }
        var parts: [String] = []
        if let now = forecast.hours[currentHour].availability {
            parts.append("当前时段（\(currentHour) 时）的空闲率为 \(Fmt.percent(now))。")
        }
        if let best = forecast.bestHour(), best.hour != currentHour {
            parts.append("未来 12 小时内，\(best.hour) 时的空闲率最高（\(Fmt.percent(best.availability))）。")
        }
        return parts.isEmpty ? "当前时段暂无足够记录。" : parts.joined()
    }

    private func footer(_ forecast: Forecast) -> String {
        if forecast.isLearning {
            return "依据已记录的 \(Fmt.duration(forecast.observedMinutes))数据统计，记录不足一周，结果仅供参考。"
        }
        return "依据近 7 天记录统计。空闲率指该时段内至少有一台设备空闲的时间占比。"
    }
}
