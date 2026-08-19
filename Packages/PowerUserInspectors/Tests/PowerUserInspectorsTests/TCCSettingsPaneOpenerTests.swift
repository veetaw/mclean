import XCTest
@testable import PowerUserInspectors

/// Only exercises URL construction — never calls `openSettingsPane(for:)`,
/// which would actually try to open real System Settings during a test run.
/// There is deliberately no test (and no production code path) for
/// revoking a grant: this type only ever opens a pane.
final class TCCSettingsPaneOpenerTests: XCTestCase {
    func testSettingsURLForKnownServicesUsesExpectedAnchor() {
        let opener = TCCSettingsPaneOpener()

        XCTAssertEqual(
            opener.settingsURL(for: .camera)?.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
        )
        XCTAssertEqual(
            opener.settingsURL(for: .fullDiskAccess)?.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        )
        XCTAssertEqual(
            opener.settingsURL(for: .microphone)?.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        )
    }

    func testSettingsURLForUnknownServiceReturnsNil() {
        let opener = TCCSettingsPaneOpener()
        let unknown = TCCServiceIdentifier(rawValue: "kTCCServiceSomethingBrandNew")
        XCTAssertNil(opener.settingsURL(for: unknown))
    }

    func testGeneralPrivacySettingsURLIsWellFormed() {
        let opener = TCCSettingsPaneOpener()
        XCTAssertEqual(
            opener.generalPrivacySettingsURL.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy"
        )
    }

    func testEveryKnownServiceProducesAValidURL() {
        let opener = TCCSettingsPaneOpener()
        let services: [TCCServiceIdentifier] = [
            .camera, .microphone, .accessibility, .fullDiskAccess, .screenCapture,
            .calendars, .contacts, .photos, .reminders, .automation,
            .inputMonitoring, .locationServices, .bluetooth, .developerTools
        ]
        for service in services {
            XCTAssertNotNil(opener.settingsURL(for: service), "missing mapping for \(service.rawValue)")
        }
    }
}
