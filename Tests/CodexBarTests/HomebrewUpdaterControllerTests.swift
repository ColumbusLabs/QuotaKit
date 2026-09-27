import Foundation
import Testing
@testable import CodexBar

@MainActor
struct HomebrewUpdaterControllerTests {
    private static let caskSource = """
    cask "quotakit" do
      version "0.66.0"
      sha256 "a12bbb5e6a6a8d539aa9bd67df6dcae6433f005c639a1d4b9595d8fc218f5616"

      url "https://github.com/ColumbusLabs/QuotaKit/releases/download/v#{version}/QuotaKit-macos-universal-#{version}.zip"
      auto_updates true
    end
    """

    @MainActor
    private final class Fixture {
        var installedVersion = "0.65.0"
        var caskSource = HomebrewUpdaterControllerTests.caskSource
        var fetchError: Error?
        var upgradeError: Error?
        var versionAfterUpgrade: String?
        var upgradeCount = 0
        var relaunchCount = 0

        func makeController() -> HomebrewUpdaterController {
            HomebrewUpdaterController(
                savedAutoCheck: false,
                dependencies: HomebrewUpdaterController.Dependencies(
                    installedVersion: { self.installedVersion },
                    fetchCaskSource: { @MainActor in
                        if let error = self.fetchError { throw error }
                        return self.caskSource
                    },
                    runUpgrade: { @MainActor in
                        self.upgradeCount += 1
                        if let error = self.upgradeError { throw error }
                        if let version = self.versionAfterUpgrade { self.installedVersion = version }
                    },
                    relaunch: { self.relaunchCount += 1 }),
                startScheduledChecks: false)
        }
    }

    @Test
    func `parses the version declared by the cask`() {
        #expect(HomebrewCaskVersion.parse(caskSource: Self.caskSource) == "0.66.0")
        #expect(HomebrewCaskVersion.parse(caskSource: "cask \"codexbar\" do\nend") == nil)
        #expect(HomebrewCaskVersion.parse(caskSource: "  version \"\"") == nil)
    }

    @Test
    func `compares versions numerically`() {
        #expect(HomebrewCaskVersion.isNewer("0.66.0", than: "0.65.0"))
        #expect(HomebrewCaskVersion.isNewer("0.100.0", than: "0.99.1"))
        #expect(!HomebrewCaskVersion.isNewer("0.65.0", than: "0.65.0"))
        #expect(!HomebrewCaskVersion.isNewer("0.64.9", than: "0.65.0"))
    }

    @Test
    func `newer cask version is offered for install`() async {
        let fixture = Fixture()
        let controller = fixture.makeController()

        await controller.performCheck()

        #expect(controller.phase == .available("0.66.0"))
        #expect(controller.updateStatus.availableVersion == "0.66.0")
    }

    @Test
    func `matching cask version reports up to date`() async {
        let fixture = Fixture()
        fixture.installedVersion = "0.66.0"
        let controller = fixture.makeController()

        await controller.performCheck()

        #expect(controller.phase == .upToDate)
        #expect(controller.updateStatus.availableVersion == nil)
    }

    @Test
    func `failed check keeps a previously found update`() async {
        let fixture = Fixture()
        let controller = fixture.makeController()
        await controller.performCheck()

        fixture.fetchError = HomebrewUpdateError.invalidCaskResponse
        await controller.performCheck()

        #expect(controller.phase == .available("0.66.0"))
        #expect(controller.updateStatus.availableVersion == "0.66.0")
    }

    @Test
    func `successful upgrade relaunches the app`() async {
        let fixture = Fixture()
        fixture.versionAfterUpgrade = "0.66.0"
        let controller = fixture.makeController()
        await controller.performCheck()

        await controller.performInstall()

        #expect(fixture.upgradeCount == 1)
        #expect(fixture.relaunchCount == 1)
        #expect(controller.updateStatus.availableVersion == nil)
        #expect(controller.updateStatus.isInstalling == false)
    }

    @Test
    func `upgrade that leaves the version unchanged fails without relaunching`() async {
        let fixture = Fixture()
        let controller = fixture.makeController()
        await controller.performCheck()

        await controller.performInstall()

        #expect(fixture.relaunchCount == 0)
        #expect(controller.phase == .failed(HomebrewUpdateError.versionUnchanged("0.65.0").localizedDescription))
        #expect(controller.updateStatus.availableVersion == "0.66.0")
        #expect(controller.updateStatus.isInstalling == false)
    }

    @Test
    func `missing brew surfaces a failure`() async {
        let fixture = Fixture()
        fixture.upgradeError = HomebrewUpdateError.brewNotFound
        let controller = fixture.makeController()
        await controller.performCheck()

        await controller.performInstall()

        #expect(fixture.relaunchCount == 0)
        #expect(controller.phase == .failed(HomebrewUpdateError.brewNotFound.localizedDescription))
    }

    @Test
    func `brew environment puts the brew prefix first on PATH`() {
        let environment = HomebrewUpdaterController.Dependencies.brewEnvironment(
            brewPath: "/opt/homebrew/bin/brew",
            base: ["HOME": "/Users/example", "PATH": "/custom"])

        #expect(environment["PATH"] == "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin")
        #expect(environment["HOME"] == "/Users/example")
        #expect(environment["HOMEBREW_NO_ENV_HINTS"] == "1")
    }

    @Test
    func `menu offers available update and shows install progress`() {
        let available = MenuDescriptor.metaSection(updateReady: false, availableUpdateVersion: "0.66.0")
        #expect(available.entries.contains { entry in
            if case let .action(title, .installUpdate) = entry { return title == "Update to 0.66.0" }
            return false
        })

        let installing = MenuDescriptor.metaSection(
            updateReady: false,
            availableUpdateVersion: "0.66.0",
            isInstallingUpdate: true)
        #expect(installing.entries.contains { entry in
            if case let .text(title, _) = entry { return title == "Updating with Homebrew…" }
            return false
        })
        #expect(!installing.entries.contains { entry in
            if case .action(_, .installUpdate) = entry { return true }
            return false
        })
    }
}
