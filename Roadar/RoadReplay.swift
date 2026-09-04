import SwiftUI

/// Synthetic road graph: these coordinates, limits and reports never describe real roads.
struct RoadReplay {
    enum Scenario: String, CaseIterable, Identifiable {
        case parallel = "Parallel road"
        case overpass = "Overpass"
        case opposite = "Opposite direction"
        case fork = "Unknown fork"
        case ambiguous = "Ambiguous position"
        case passed = "Passed & expired"
        case weak = "Weak GPS"
        case stopped = "Stationary"
        var id: String { rawValue }
    }

    let scenario: Scenario
    let progress: Double
    let now: Date

    var roads: [RoadEdge] {
        [
            RoadEdge(id: "east", name: "Demo East Road", start: .init(x: 0, y: 0), end: .init(x: 400, y: 0), elevation: 0, speedLimitMPH: 35, successors: scenario == .fork ? ["continue", "branch"] : ["continue"]),
            RoadEdge(id: "west", name: "Demo Westbound", start: .init(x: 400, y: 0), end: .init(x: 0, y: 0), elevation: 0),
            RoadEdge(id: "parallel", name: "Demo Frontage Road", start: .init(x: 0, y: 24), end: .init(x: 400, y: 24), elevation: 0),
            RoadEdge(id: "bridge", name: "Demo Overpass", start: .init(x: 200, y: -200), end: .init(x: 200, y: 200), elevation: 8),
            RoadEdge(id: "continue", name: "Demo East Road", start: .init(x: 400, y: 0), end: .init(x: 800, y: 0), elevation: 0, speedLimitMPH: 35),
            RoadEdge(id: "branch", name: "Demo Fork", start: .init(x: 400, y: 0), end: .init(x: 750, y: -150), elevation: 0)
        ]
    }

    var sample: RoadSample {
        RoadSample(point: .init(x: scenario == .overpass ? 200 : progress, y: scenario == .ambiguous ? 12 : 0),
                   course: 90, accuracy: scenario == .weak ? 80 : 5,
                   speed: scenario == .stopped ? 0 : 15, timestamp: now)
    }

    var reports: [RoadReport] {
        let recent = now.addingTimeInterval(-120)
        return [
            RoadReport(id: "hazard", edgeID: "east", offset: 260, title: "Simulated hazard", createdAt: recent),
            RoadReport(id: "hazard", edgeID: "east", offset: 260, title: "Duplicate hazard", createdAt: recent.addingTimeInterval(-10)),
            RoadReport(id: "behind", edgeID: "east", offset: 20, title: "Already passed", createdAt: recent),
            RoadReport(id: "old", edgeID: "east", offset: 350, title: "Expired report", createdAt: now.addingTimeInterval(-3600)),
            RoadReport(id: "parallel", edgeID: "parallel", offset: 260, title: "Frontage road report", createdAt: recent),
            RoadReport(id: "opposite", edgeID: "west", offset: 100, title: "Opposite direction report", createdAt: recent),
            RoadReport(id: "bridge", edgeID: "bridge", offset: 260, title: "Overpass report", createdAt: recent),
            RoadReport(id: "continuation", edgeID: "continue", offset: 100, title: "Simulated police report", createdAt: recent),
            RoadReport(id: "fork", edgeID: "branch", offset: 80, title: "After unknown turn", createdAt: recent)
        ]
    }

    var context: RoadContext { RoadMatcher().evaluate(sample: sample, roads: roads, reports: reports, now: now) }

    var explanation: String {
        switch scenario {
        case .parallel: "The nearby frontage road has a different directed segment. Its report is excluded."
        case .overpass: "The driver is traveling east underneath the northbound overpass. Its report is excluded."
        case .opposite: "The westbound report shares road geometry but faces the opposite direction. It is excluded."
        case .fork: "With no destination, the intended branch is unknown. Reports beyond the fork are withheld."
        case .ambiguous: "This position fits both parallel roads. No road or reports are presented as certain."
        case .passed: "Move forward to pass the hazard. Passed, duplicate and expired reports are excluded."
        case .weak: "Poor location accuracy prevents a confident match. Reports are withheld."
        case .stopped: "A stationary sample has no reliable travel direction. Reports are withheld."
        }
    }
}

struct RoadReplayView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scenario: RoadReplay.Scenario = .parallel
    @State private var progress = 80.0
    private var replay: RoadReplay { RoadReplay(scenario: scenario, progress: progress, now: .now) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label("SIMULATED · No live road data", systemImage: "testtube.2")
                        .font(.headline).foregroundStyle(.orange)
                    Text("A destination-free replay of invented roads and reports. It does not use your location.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Picker("Replay scenario", selection: $scenario) {
                        ForEach(RoadReplay.Scenario.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    diagram
                        .frame(height: 200)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("Synthetic road diagram. Driver travels east. Frontage road runs parallel; overpass crosses north–south.")
                    Text(replay.explanation).font(.subheadline)
                    if scenario != .overpass {
                        Text("Replay position: \(Int(progress)) m east").font(.caption)
                        Slider(value: $progress, in: 40...350, step: 10)
                            .accessibilityLabel("Move simulated driver forward")
                    }
                    let context = replay.context
                    Text(context.road?.name ?? "Road uncertain").font(.title3.bold())
                    Text("Simulated speed limit: \(context.road?.speedLimitMPH.map { "\($0) mph" } ?? "Unknown")")
                    Text(context.message).font(.subheadline).foregroundStyle(.secondary)
                    Text("Simulated reports ahead").font(.headline)
                    ForEach(context.reports) { ahead in
                        Label("\(ahead.report.title) · \(Int(ahead.distance)) m ahead · 2 min old", systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                    }
                    if context.reports.isEmpty {
                        Text("No eligible simulated reports. This does not mean the road is clear.")
                            .font(.subheadline)
                    }
                    Text("Gray roads and dots are excluded. Orange dots are eligible reports ahead. The blue dot is the simulated driver.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Road replay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var diagram: some View {
        Canvas { context, size in
            let fixture = replay
            func screen(_ point: RoadPoint) -> CGPoint {
                CGPoint(x: 18 + point.x / 800 * (size.width - 36), y: size.height / 2 - point.y / 450 * (size.height - 20))
            }
            for edge in fixture.roads where edge.id != "west" {
                var path = Path()
                path.move(to: screen(edge.start))
                path.addLine(to: screen(edge.end))
                context.stroke(path, with: .color(edge.id == fixture.context.road?.id ? .teal : .gray.opacity(0.5)), lineWidth: 4)
            }
            let eligible = Set(fixture.context.reports.map(\.id))
            for report in fixture.reports where report.id != "hazard" || report.title != "Duplicate hazard" {
                if let edge = fixture.roads.first(where: { $0.id == report.edgeID }) {
                    let p = screen(edge.point(at: report.offset))
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)), with: .color(eligible.contains(report.id) ? .orange : .gray))
                }
            }
            let driver = screen(fixture.sample.point)
            context.fill(Path(ellipseIn: CGRect(x: driver.x - 7, y: driver.y - 7, width: 14, height: 14)), with: .color(.blue))
            context.draw(Text("E →").font(.caption.bold()), at: CGPoint(x: size.width - 30, y: 20))
        }
    }
}
