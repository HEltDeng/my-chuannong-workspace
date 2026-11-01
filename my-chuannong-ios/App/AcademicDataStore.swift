import Foundation
import Observation
import Vision
import ImageIO

@MainActor @Observable final class AcademicDataStore {
    static let shared = AcademicDataStore()
    private(set) var data: AcademicCalendarData?
    private(set) var refreshing = false
    private(set) var message: String?
    private let file: URL
    private init() {
        file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "public-academic-verified.json")
        func decode(_ url: URL) -> AcademicCalendarData? { guard let bytes = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(AcademicCalendarData.self, from: bytes), (try? AcademicCalendarRules.validate(value)) != nil else { return nil }; return value }
        let seed = Bundle.main.url(forResource: "sicau-academic", withExtension: "json").flatMap(decode)
        data = decode(file) ?? seed
    }
    func refresh(force: Bool = false) async {
        guard !refreshing, let active = data else { return }
        let last = UserDefaults.standard.double(forKey: "academic.lastAttempt")
        guard force || Date.now.timeIntervalSince1970 - last >= Double(min(168, max(1, active.checkIntervalHours ?? 24))) * 3600 else { return }
        refreshing = true; defer { refreshing = false }
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: "academic.lastAttempt")
        do {
            let candidate = try await OfficialAcademicSource.check(active)
            try Task.checkCancellation(); try AcademicCalendarRules.validate(candidate)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(candidate).write(to: file, options: .atomic)
            data = candidate; message = "已核对学校官方来源"
        } catch is CancellationError {} catch { message = error.localizedDescription }
    }
}
private final class OfficialAcademicRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? { request.url.map { AcademicCalendarRules.validSource($0.absoluteString) } == true ? request : nil }
}
nonisolated private enum OfficialAcademicSource {
    struct Resource: Sendable { var source: AcademicCalendarData.Source; var bytes: Data }
    struct Discovery: Sendable { var year: String; var resources: [Resource]; var fingerprint: String }
    static func check(_ active: AcademicCalendarData) async throws -> AcademicCalendarData {
        let config = URLSessionConfiguration.ephemeral; config.httpCookieStorage = nil; config.urlCache = nil; config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 40
        let session = URLSession(configuration: config, delegate: OfficialAcademicRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let html = String(decoding: try await download(AcademicCalendarRules.source, session: session), as: UTF8.self)
        let text = html.replacingOccurrences(of: "(?is)<script\\b[^>]*>.*?</script>|<style\\b[^>]*>.*?</style>", with: "", options: .regularExpression).replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let years = Set(TimetableRules.matches("(20[0-9]{2})[-—–](20[0-9]{2})学年", text).map { $0[1] + "-" + $0[2] })
        guard years.count == 1, let year = years.first else { throw APIError.server(422, "官方学年信息需核对，已保留本地校历") }
        let urls = try imageURLs(html)
        var resources: [Resource] = []
        for url in urls { let data = try await download(url, session: session); resources.append(Resource(source: .init(url: url, sha256: AcademicCalendarRules.sha256(data)), bytes: data)) }
        let fingerprint = AcademicCalendarRules.sha256(Data(resources.map { $0.source.sha256 }.sorted().joined().utf8))
        let found = Discovery(year: year, resources: resources, fingerprint: fingerprint)
        if fingerprint != active.contentFingerprint || year != active.academicYear {
            do { return try await Task.detached(priority: .utility) { try OfficialCalendarOCR.parse(found, active: active) }.value }
            catch is CancellationError { throw CancellationError() }
            catch { throw APIError.server(422, "官方原件有变化，解析待核对；保留已验证校历") }
        }
        var next = active
        guard let oldSources = active.sourceResources else { throw SchoolFailure.structure }
        next.sourceResources = try oldSources.map { old in guard let match = resources.first(where: { $0.source.sha256 == old.sha256 }) else { throw SchoolFailure.structure }; return match.source }
        next.terms = active.terms.map { old in var term = old; term.sourceResource = next.sourceResources?.first(where: { $0.sha256 == term.sourceFingerprint })?.url ?? term.sourceResource; return term }
        next.checkedAt = ISO8601DateFormatter().string(from: .now); return next
    }
    private static func download(_ value: String, session: URLSession) async throws -> Data {
        guard AcademicCalendarRules.validSource(value), let url = URL(string: value) else { throw APIError.invalidRoute }
        let (bytes, response) = try await session.bytes(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), http.url.map({ AcademicCalendarRules.validSource($0.absoluteString) }) == true, response.expectedContentLength <= 8 * 1024 * 1024 else { throw APIError.server(422, "官方来源暂不可用，已保留本地校历") }
        var result = Data(); for try await byte in bytes { if result.count >= 8 * 1024 * 1024 { throw APIError.invalidResponse }; result.append(byte) }; return result
    }
    /// Only image elements inside the official content container are accepted. No scripts are run.
    private static func imageURLs(_ html: String) throws -> [String] {
        let tags = TimetableRules.matches("(?is)<\\s*(/?)\\s*([a-zA-Z][a-zA-Z0-9]*)\\b([^>]*)>", html)
        func attribute(_ name: String, _ attributes: String) -> String? { TimetableRules.matches("(?i)\\b" + name + "\\s*=\\s*[\"']([^\"']+)[\"']", attributes).first?[1].replacingOccurrences(of: "&amp;", with: "&") }
        var root: String?, depth = 0, values: [String] = []
        for tag in tags {
            let closing = tag[1] == "/", name = tag[2].lowercased(), attributes = tag[3]
            if root == nil { if !closing && attribute("id", attributes) == "vsb_content" { root = name; depth = 1 }; continue }
            if name == root { depth += closing ? -1 : 1; if depth == 0 { break } }
            if name == "img", !closing, let raw = attribute("src", attributes), let url = URL(string: raw, relativeTo: URL(string: AcademicCalendarRules.source))?.absoluteURL {
                guard AcademicCalendarRules.validSource(url.absoluteString), url.path.hasPrefix("/__local/") else { throw SchoolFailure.structure }
                if !values.contains(url.absoluteString) { values.append(url.absoluteString) }
            }
        }
        guard (1...4).contains(values.count), depth == 0 else { throw APIError.server(422, "官方校历版式有变化，核对中；保留已验证校历") }; return values
    }
}
nonisolated private enum OfficialCalendarOCR {
    static func parse(_ found: OfficialAcademicSource.Discovery, active: AcademicCalendarData) throws -> AcademicCalendarData {
        guard found.resources.count == 2, let year = Int(found.year.prefix(4)), let oldYear = active.academicYear.flatMap({ Int($0.prefix(4)) }), (oldYear...oldYear + 1).contains(year) else { throw SchoolFailure.structure }
        var notes: [AcademicCalendarRules.Notes]?, periods: [AcademicCalendarData.Period]?, calendarSource: AcademicCalendarData.Source?, periodsSource: AcademicCalendarData.Source?
        for resource in found.resources {
            try Task.checkCancellation()
            guard let source = CGImageSourceCreateWithData(resource.bytes as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil), (600...4000).contains(image.width), (600...5000).contains(image.height) else { throw SchoolFailure.structure }
            let overview = try recognize(image, scale: 2, maxDimension: 4000)
            if overview.contains("第一节") && overview.contains("第十节") {
                guard periods == nil else { throw SchoolFailure.structure }
                let crop = try crop(image, x: 0.64, y: 0.35, width: 0.30, height: 0.31)
                let first = try AcademicCalendarRules.periods(recognize(crop, scale: 3)), second = try AcademicCalendarRules.periods(recognize(crop, scale: 4))
                guard first == second else { throw SchoolFailure.structure }; periods = first; periodsSource = resource.source
            } else {
                guard notes == nil else { throw SchoolFailure.structure }
                var readings: [AcademicCalendarRules.Notes] = []
                for semester in 1...2 {
                    let crop = try crop(image, x: semester == 1 ? 0.14 : 0.58, y: 0.83, width: 0.33, height: 0.15)
                    let candidates = try (3...5).compactMap { scale -> AcademicCalendarRules.Notes? in try Task.checkCancellation(); return try? AcademicCalendarRules.notes(recognize(crop, scale: scale), year: year, semester: semester) }
                    guard candidates.count >= 2, let first = candidates.first, candidates.allSatisfy({ $0 == first }) else { throw SchoolFailure.structure }; readings.append(first)
                }
                notes = readings; calendarSource = resource.source
            }
        }
        guard let notes, let periods, let calendarSource, let periodsSource else { throw SchoolFailure.structure }
        var next = active; let version = String(found.fingerprint.prefix(12)); let now = ISO8601DateFormatter().string(from: .now)
        let terms = try notes.enumerated().map { index, n -> AcademicCalendarData.Term in
            let number = index + 1, code = found.year + "-" + String(number)
            func event(_ name: String, _ type: String, _ start: Date, _ end: Date? = nil) -> AcademicCalendarData.Event { .init(name: name, start: AcademicCalendarRules.day(start), end: AcademicCalendarRules.day(end ?? start), type: type, source: AcademicCalendarRules.source) }
            let old = active.terms.first { $0.id == code }
            if let old, old.semesterStart != AcademicCalendarRules.day(n.teaching) || old.semesterEnd != AcademicCalendarRules.day(n.practiceEnd) { throw SchoolFailure.structure }
            let events = [event("开学上班", "opening", n.opening), event("报到注册", "registration", n.registrationStart, n.registrationEnd), event("正式行课", "teaching", n.teaching), event("实践周", "practice", n.practiceStart, n.practiceEnd), event(number == 1 ? "寒假" : "暑假开始", number == 1 ? "vacation" : "vacation_start", n.vacationStart, n.vacationEnd)] + (old?.events.filter { $0.type == "festival" } ?? [])
            let calendar = AcademicCalendarRules.calendar, first = calendar.dateInterval(of: .month, for: n.opening)!.start, last = AcademicCalendarRules.adding(-1, to: calendar.dateInterval(of: .month, for: n.practiceEnd)!.end)
            return AcademicCalendarData.Term(semesterCode: code, title: found.year + "学年", subtitle: number == 1 ? "第一学期" : "第二学期", calendarStart: AcademicCalendarRules.day(first), calendarEnd: AcademicCalendarRules.day(n.vacationEnd ?? last), semesterStart: AcademicCalendarRules.day(n.teaching), semesterEnd: AcademicCalendarRules.day(n.practiceEnd), teachingWeeks: AcademicCalendarRules.days(n.teaching, n.practiceEnd) / 7 + 1, weekRule: "MONDAY_CONTINUOUS", sourceResource: calendarSource.url, sourceFingerprint: calendarSource.sha256, dataVersion: version, events: events)
        }
        var revisions = active.revisions ?? []
        if !revisions.contains(where: { $0.fingerprint == active.contentFingerprint }) { revisions.append(.init(version: active.version, fingerprint: active.contentFingerprint ?? "", sources: active.sourceResources ?? [], replacedAt: now)) }
        next.revisions = Array(revisions.suffix(8)); next.academicYear = found.year; next.version = "sicau-" + found.year + "-" + version; next.contentFingerprint = found.fingerprint
        next.terms = active.terms.filter { old in !terms.contains { $0.id == old.id } } + terms; next.periods = periods; next.periodsVersion = version; next.sourceResources = [calendarSource, periodsSource]; next.checkedAt = now
        try AcademicCalendarRules.validate(next); return next
    }
    private static func crop(_ image: CGImage, x: Double, y: Double, width: Double, height: Double) throws -> CGImage {
        guard let value = image.cropping(to: CGRect(x: Double(image.width) * x, y: Double(image.height) * y, width: Double(image.width) * width, height: Double(image.height) * height).integral) else { throw SchoolFailure.structure }; return value
    }
    private static func recognize(_ image: CGImage, scale: Int, maxDimension: Int = 5000) throws -> String {
        try Task.checkCancellation()
        let factor = min(Double(scale), Double(maxDimension) / Double(max(image.width, image.height))), width = max(1, Int(Double(image.width) * factor)), height = max(1, Int(Double(image.height) * factor))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw SchoolFailure.structure }
        context.interpolationQuality = .high; context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height)); guard let scaled = context.makeImage() else { throw SchoolFailure.structure }
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.recognitionLanguages = ["zh-Hans", "en-US"]; request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: scaled).perform([request]); try Task.checkCancellation()
        let observations = (request.results ?? []).filter { ($0.topCandidates(1).first?.confidence ?? 0) >= 0.65 }.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
        var rows: [[VNRecognizedTextObservation]] = []
        for observation in observations { if let last = rows.last?.first, abs(last.boundingBox.midY - observation.boundingBox.midY) < observation.boundingBox.height / 2 { rows[rows.count - 1].append(observation) } else { rows.append([observation]) } }
        return rows.map { $0.sorted { $0.boundingBox.minX < $1.boundingBox.minX }.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ") }.joined(separator: "\n")
    }
}
