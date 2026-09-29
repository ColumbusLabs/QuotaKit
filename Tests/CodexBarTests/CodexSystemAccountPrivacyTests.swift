import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct CodexSystemAccountPrivacyTests {
    private static let firstSlot = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private static let secondSlot = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    @Test
    func `private submenu replaces arbitrary account labels with stable ordinals`() {
        let accounts = [
            Self.account("managed-b", email: "alex@example.com", workspace: "Private Org", storedID: Self.firstSlot),
            Self.account("managed-a", email: "blair@example.com", workspace: "Personal", storedID: Self.secondSlot),
            Self.account("owner@example.com", email: "casey@example.com", workspace: "Team casey@example.com"),
        ]

        let items = Self.items(Self.projection(accounts), hide: true)

        #expect(items.map(\.title) == ["Account 1", "Account 2", "Account 3"])
        #expect(items.allSatisfy { !$0.title.contains("@") })
        #expect(items.allSatisfy { !$0.title.contains("Private") && !$0.title.contains("Org") })
    }

    @Test
    func `privacy off preserves exact display names`() {
        let accounts = [
            Self.account("first", email: "same@example.com", workspace: "Personal", storedID: Self.firstSlot),
            Self.account("second", email: "same@example.com", workspace: "Team", storedID: Self.secondSlot),
        ]
        let projection = Self.projection(accounts)

        let items = Self.items(projection, hide: false)

        #expect(items.map(\.title) == projection.visibleAccounts.map(\.displayName))
        #expect(items.map(\.title) == [
            "same@example.com — Personal",
            "same@example.com — Team",
        ])
    }

    @Test
    func `privacy changes only titles and preserves promotion state`() {
        let projection = Self.projection([
            Self.account("live", email: "live@example.com", storedID: Self.firstSlot),
            Self.account("managed", email: "managed@example.com", storedID: Self.secondSlot),
            Self.account("external", email: "external@example.com"),
        ], live: "live")

        let publicItems = Self.items(projection, hide: false)
        let privateItems = Self.items(projection, hide: true)

        #expect(privateItems.map(\.title) == ["Account 1", "Account 2", "Account 3"])
        #expect(privateItems.map(\.action) == publicItems.map(\.action))
        #expect(privateItems.map(\.isEnabled) == publicItems.map(\.isEnabled))
        #expect(privateItems.map(\.isChecked) == publicItems.map(\.isChecked))
        #expect(publicItems.map(\.action) == [
            .requestCodexSystemPromotion(Self.firstSlot),
            .requestCodexSystemPromotion(Self.secondSlot),
            nil,
        ])
        #expect(publicItems.map(\.isEnabled) == [false, true, false])
        #expect(publicItems.map(\.isChecked) == [true, false, false])

        let blockedItems = Self.items(projection, hide: true, blocked: true)
        #expect(blockedItems.map(\.action) == privateItems.map(\.action))
        #expect(blockedItems.map(\.isChecked) == privateItems.map(\.isChecked))
        #expect(blockedItems.allSatisfy { !$0.isEnabled })
    }

    @Test
    func `private ordinals survive display reordering and promotion to the live identity`() {
        let accounts = [
            Self.account("managed-b", email: "b@example.com", storedID: Self.firstSlot),
            Self.account("managed-a", email: "a@example.com", storedID: Self.secondSlot),
        ]

        let original = Self.items(Self.projection(accounts), hide: true)
        let reversed = Self.items(Self.projection(Array(accounts.reversed())), hide: true)
        let promoted = Self.items(Self.projection([
            Self.account("live-b", email: "b@example.com", storedID: Self.firstSlot),
            accounts[1],
        ], live: "live-b"), hide: true)

        #expect(original.map(\.title) == ["Account 1", "Account 2"])
        #expect(reversed.map(\.title) == ["Account 2", "Account 1"])
        #expect(promoted.map(\.title) == original.map(\.title))
        #expect(promoted.map(\.isChecked) == [true, false])
    }

    @Test
    func `existing submenu visibility rules remain intact when privacy changes`() {
        for hide in [false, true] {
            #expect(Self.items(Self.projection([]), hide: hide).isEmpty)
            let singleLive = Self.projection(
                [Self.account("live", email: "live@example.com")],
                live: "live")
            #expect(Self.items(singleLive, hide: hide).isEmpty)

            let singleStored = Self.projection([
                Self.account("stored", email: "stored@example.com", storedID: Self.firstSlot),
            ])
            #expect(Self.items(singleStored, hide: hide).count == 1)
            #expect(Self.items(singleStored, hide: hide, blocked: true).isEmpty)

            let multipleStored = Self.projection([
                Self.account("first", email: "first@example.com", storedID: Self.firstSlot),
                Self.account("second", email: "second@example.com", storedID: Self.secondSlot),
            ])
            let blockedMultiple = Self.items(multipleStored, hide: hide, blocked: true)
            #expect(blockedMultiple.count == 2)
            #expect(blockedMultiple.allSatisfy { !$0.isEnabled })
        }
    }

    private static func items(
        _ projection: CodexVisibleAccountProjection,
        hide: Bool,
        blocked: Bool = false) -> [MenuDescriptor.SubmenuItem]
    {
        CodexProviderImplementation.systemAccountMenuItems(
            projection: projection,
            hidePersonalInfo: hide,
            isInteractionBlocked: blocked)
    }

    private static func projection(
        _ accounts: [CodexVisibleAccount],
        live: String? = nil) -> CodexVisibleAccountProjection
    {
        CodexVisibleAccountProjection(
            visibleAccounts: accounts,
            activeVisibleAccountID: nil,
            liveVisibleAccountID: live,
            hasUnreadableAddedAccountStore: false)
    }

    private static func account(
        _ id: String,
        email: String,
        workspace: String? = nil,
        storedID: UUID? = nil) -> CodexVisibleAccount
    {
        CodexVisibleAccount(
            id: id,
            email: email,
            workspaceLabel: workspace,
            storedAccountID: storedID,
            selectionSource: .liveSystem,
            isActive: false,
            isLive: false,
            canReauthenticate: false,
            canRemove: false)
    }
}
