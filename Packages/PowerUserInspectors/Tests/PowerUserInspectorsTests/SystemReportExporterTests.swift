import XCTest
@testable import PowerUserInspectors

final class SystemReportExporterTests: TempDirTestCase {
    private var applicationsDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        applicationsDir = tempDir.appendingPathComponent("Applications")
        try TestSupport.makeDirectory(at: applicationsDir)

        let bundleURL = applicationsDir.appendingPathComponent("Foo.app")
        let contentsURL = bundleURL.appendingPathComponent("Contents")
        try TestSupport.makeDirectory(at: contentsURL)
        let info: [String: Any] = [
            "CFBundleName": "Foo",
            "CFBundleIdentifier": "com.example.foo",
            "CFBundleShortVersionString": "1.0"
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plistData.write(to: contentsURL.appendingPathComponent("Info.plist"))
        try TestSupport.makeBinaryFile(at: contentsURL.appendingPathComponent("MacOS/Foo"), size: 1000)
    }

    private func makeExporter(runner: ExternalCommandRunning) -> SystemReportExporter {
        SystemReportExporter(
            appsInspector: InstalledAppsInspector(lastUsedProvider: NullAppLastUsedDateProvider()),
            packageExplorer: PackageExplorer(commandRunner: runner)
        )
    }

    func testBuildReportAggregatesAppsAndPackageCounts() async {
        let runner = FakeCommandRunner(resultsByExecutable: [
            "pip3": makeResult(#"[{"name": "requests", "version": "1.0"}, {"name": "flask", "version": "2.0"}]"#),
            "brew": makeResult("git 2.43.0\n")
        ])
        let exporter = makeExporter(runner: runner)

        let report = await exporter.buildReport(applicationDirectories: [applicationsDir.path])

        XCTAssertEqual(report.installedApps.count, 1)
        XCTAssertEqual(report.installedApps.first?.bundleIdentifier, "com.example.foo")
        XCTAssertGreaterThanOrEqual(report.totalAppsSizeBytes, 1000)
        XCTAssertEqual(report.packageCounts["pip"], 2)
        XCTAssertEqual(report.packageCounts["homebrew"], 1)
        XCTAssertEqual(report.packageCounts["npm"], 0)
        XCTAssertNil(report.packageCounts["goModules"])
        XCTAssertNotNil(report.diskUsage.volumeTotalBytes)
    }

    func testExportJSONProducesDecodableReport() async throws {
        let exporter = makeExporter(runner: FakeCommandRunner())

        let data = try await exporter.exportJSON(applicationDirectories: [applicationsDir.path])

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SystemReport.self, from: data)
        XCTAssertEqual(decoded.installedApps.count, 1)
    }

    func testExportPDFAlwaysThrowsNotImplemented() async {
        let exporter = makeExporter(runner: FakeCommandRunner())
        XCTAssertThrowsError(try exporter.exportPDF()) { error in
            XCTAssertEqual(error as? SystemReportError, .pdfExportNotImplemented)
        }
    }

    func testBuildReportIncludesGoModulesWhenDirectoryProvided() async {
        let runner = FakeCommandRunner(resultsByExecutable: [
            "go": makeResult("main\ngithub.com/pkg/errors v0.9.1\n")
        ])
        let exporter = makeExporter(runner: runner)

        let report = await exporter.buildReport(applicationDirectories: [applicationsDir.path], goModuleDirectory: tempDir.path)

        XCTAssertEqual(report.packageCounts["goModules"], 1)
    }
}
