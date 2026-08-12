import Foundation

/// Capability boundary for operations whose Keychain behavior QuotaKit cannot make non-interactive.
///
/// Claude CLI children and reads of Claude Code's Keychain item are denied by default. The capability
/// is scoped only around an explicit QuotaKit CLI invocation or an explicit Mac user action.
public enum ClaudeOpaqueOperationContext {
    enum Capability: Sendable, Equatable {
        case denied
        case explicitUserOrCLI
    }

    @TaskLocal static var capability: Capability = .denied

    public static var isAllowed: Bool {
        self.capability == .explicitUserOrCLI || ProviderInteractionContext.current == .userInitiated
    }

    static func isExplicit(runtime: ProviderRuntime) -> Bool {
        runtime == .cli || ProviderInteractionContext.current == .userInitiated
    }

    static func withExplicitAccessIfAllowed<T>(
        runtime: ProviderRuntime,
        operation: () throws -> T) rethrows -> T
    {
        guard self.isExplicit(runtime: runtime) else { return try operation() }
        return try self.$capability.withValue(.explicitUserOrCLI, operation: operation)
    }

    static func withExplicitAccessIfAllowed<T>(
        runtime: ProviderRuntime,
        operation: () async throws -> T) async rethrows -> T
    {
        guard self.isExplicit(runtime: runtime) else { return try await operation() }
        return try await self.$capability.withValue(.explicitUserOrCLI, operation: operation)
    }

    public static func withExplicitCLIAccess<T>(operation: () throws -> T) rethrows -> T {
        try self.$capability.withValue(.explicitUserOrCLI, operation: operation)
    }

    public static func withExplicitCLIAccess<T>(
        operation: () async throws -> T) async rethrows -> T
    {
        try await self.$capability.withValue(.explicitUserOrCLI, operation: operation)
    }
}
