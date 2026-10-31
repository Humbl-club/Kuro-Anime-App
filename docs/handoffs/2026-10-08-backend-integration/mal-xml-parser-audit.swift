import Foundation
@main struct ImportAudit {
    static func main() throws {
        let row = "<anime><series_animedb_id>7</series_animedb_id><my_status>Watching</my_status><my_watched_episodes>2</my_watched_episodes><my_score>8</my_score></anime>"
        let source = "<myanimelist>\(row)</myanimelist>"
        let valid = try MALExportParser.parse(Data(source.utf8))[0].draft()
        print("valid XML raw score=\(valid.scoreRaw ?? "nil") scale=\(valid.scoreScale) normalizedRating=\(valid.normalizedRating.map(String.init) ?? "nil")")
        let negative = source.replacingOccurrences(of: "<my_watched_episodes>2", with: "<my_watched_episodes>-2")
        print("negative progress XML accepted=\(try MALExportParser.parse(Data(negative.utf8))[0].progress ?? 999)")
        let invalidStatus = source.replacingOccurrences(of: "Watching", with: "Banana")
        print("unknown status XML accepted=\(try MALExportParser.parse(Data(invalidStatus.utf8))[0].status)")
        let fakeRoot = "<outer><myanimelist/>\(row)</outer>"
        print("entry outside myanimelist XML accepted count=\(try MALExportParser.parse(Data(fakeRoot.utf8)).count)")
    }
}
