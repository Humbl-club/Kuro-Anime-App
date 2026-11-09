import Foundation
import KuroLibrary
import Testing

@Suite("MAL export parser: manga element names")
struct MALExportParserTests {
    private static func document(_ rows: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <myanimelist>
          <myinfo><user_export_type>2</user_export_type></myinfo>
        \(rows)
        </myanimelist>
        """.utf8)
    }

    /// A row shaped like a MyAnimeList manga export: `manga_mangadb_id` and `manga_title`, plus elements the
    /// parser does not read.
    @Test func parsesARowShapedLikeARealMangaExport() throws {
        let items = try MALExportParser.parse(Self.document("""
          <manga>
            <manga_mangadb_id>2</manga_mangadb_id>
            <manga_title><![CDATA[Berserk]]></manga_title>
            <manga_volumes>0</manga_volumes>
            <manga_chapters>0</manga_chapters>
            <my_id>0</my_id>
            <my_read_volumes>4</my_read_volumes>
            <my_read_chapters>37</my_read_chapters>
            <my_start_date>2024-03-00</my_start_date>
            <my_finish_date>0000-00-00</my_finish_date>
            <my_score>9</my_score>
            <my_status>Reading</my_status>
            <update_on_import>1</update_on_import>
          </manga>
        """))
        let item = try #require(items.first)
        #expect(items.count == 1)
        #expect(item.medium == "manga" && item.externalId == "2")
        #expect(item.sourceTitle == "Berserk")
        #expect(item.status == "reading" && item.progress == 37 && item.volumesProgress == 4)
        #expect(item.scoreRaw == "9")
        #expect(item.startedRaw == "2024-03-00" && item.finishedRaw == nil)
    }

    @Test func stillParsesTheOlderSeriesMangaElements() throws {
        let items = try MALExportParser.parse(Self.document("""
          <manga>
            <series_mangadb_id>42</series_mangadb_id>
            <series_title>Old Shape</series_title>
            <my_read_chapters>3</my_read_chapters>
            <my_status>Completed</my_status>
          </manga>
        """))
        let item = try #require(items.first)
        #expect(item.externalId == "42" && item.sourceTitle == "Old Shape" && item.progress == 3)
    }

    @Test func rejectsAMangaRowWhoseTwoIdElementsDisagree() throws {
        let disagreeing = Self.document("""
          <manga>
            <manga_mangadb_id>2</manga_mangadb_id>
            <series_mangadb_id>3</series_mangadb_id>
            <my_status>Reading</my_status>
          </manga>
        """)
        #expect(throws: MALExportError.malformed) { try MALExportParser.parse(disagreeing) }

        let agreeing = try MALExportParser.parse(Self.document("""
          <manga>
            <manga_mangadb_id>2</manga_mangadb_id>
            <series_mangadb_id>2</series_mangadb_id>
            <my_status>Reading</my_status>
          </manga>
        """))
        #expect(agreeing.map(\.externalId) == ["2"])
    }

    @Test func mangaTitlePrefersMangaTitleAndFallsBackToSeriesTitle() throws {
        let items = try MALExportParser.parse(Self.document("""
          <manga>
            <manga_mangadb_id>1</manga_mangadb_id>
            <manga_title>Current</manga_title>
            <series_title>Older</series_title>
            <my_status>Reading</my_status>
          </manga>
          <manga>
            <manga_mangadb_id>2</manga_mangadb_id>
            <manga_title></manga_title>
            <series_title>Fallback</series_title>
            <my_status>Reading</my_status>
          </manga>
          <manga>
            <manga_mangadb_id>3</manga_mangadb_id>
            <my_status>Reading</my_status>
          </manga>
        """))
        #expect(items.map(\.sourceTitle) == ["Current", "Fallback", nil])
    }

    /// Anime rows are unchanged: the manga names do not stand in for `series_animedb_id`.
    @Test func animeRowsStillNeedSeriesAnimedbId() throws {
        let wrongElement = Self.document("""
          <anime>
            <manga_mangadb_id>5</manga_mangadb_id>
            <my_status>Watching</my_status>
          </anime>
        """)
        #expect(throws: MALExportError.malformed) { try MALExportParser.parse(wrongElement) }
    }
}
