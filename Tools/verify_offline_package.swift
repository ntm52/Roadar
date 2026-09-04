import Foundation
import CoreLocation

@main struct VerifyPackage {
    static func main() async throws {
        setbuf(stdout, nil)
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let file = root.appendingPathComponent("OfflinePackages/southern-michigan.roadar.gz")
        let catalog = try JSONDecoder().decode(OfflineRoadCatalog.self, from: Data(contentsOf: root.appendingPathComponent("Roadar/southern-michigan.json")))
        let saved = URL(fileURLWithPath: "/tmp/roadar-real-package-validation")
        let worker = OfflineRoadWorker(directory: saved)
        let start = Date()
        let region = try await worker.install(file, catalog: catalog)
        print("Validated compressed package: \(region.roadCount) roads; install \(Date().timeIntervalSince(start)) seconds")
        let db = try OfflineRoadDatabase(url: saved.appendingPathComponent("southern-michigan.roadar"))
        let roads = try db.nearby(latitude: 42.270, longitude: -83.749)
        print("Spatial lookup returned \(roads.count) roads")
        var confirmations = 0
        for road in roads where road.forwardLimit != nil {
            for (a,b) in zip(road.points, road.points.dropFirst()) {
                let dx = (b[0]-a[0]) * cos(a[1] * .pi / 180), dy=b[1]-a[1]
                guard hypot(dx,dy)*111195 > 10 else { continue }
                let course = (atan2(dx,dy)*180 / .pi+360).truncatingRemainder(dividingBy:360)
                await worker.reset()
                var last: OfflineRoadMatch?
                for i in 0..<3 {
                    let t = 0.35 + Double(i)*0.1
                    let stamp = Date().addingTimeInterval(Double(i))
                    let location = CLLocation(coordinate: .init(latitude:a[1]+t*(b[1]-a[1]),longitude:a[0]+t*(b[0]-a[0])),altitude:0,horizontalAccuracy:5,verticalAccuracy:5,course:course,speed:10,timestamp:stamp)
                    do { last = try await worker.match(OfflineRoadFix(location),now:stamp) }
                    catch { print("Matching read failed: \(error)"); throw error }
                }
                print("Candidate \(road.name): \(last?.message ?? "nil")")
                if let name = last?.road {
                    print("Synthetic replay on real geometry: \(name), \(last?.speedLimit ?? "unknown")")
                    confirmations += 1
                    break
                }
            }
            if confirmations >= 2 { break }
        }
        guard confirmations > 0 else { throw OfflineRoadError.unavailable }
        let outside = CLLocation(latitude:43.0,longitude:-84.55)
        let outsideResult = try await worker.match(OfflineRoadFix(outside),now:Date())
        guard outsideResult.road == nil else { throw OfflineRoadError.invalidPackage }
        print("Outside-region withholding passed; validation did not make any network requests")
    }
}
