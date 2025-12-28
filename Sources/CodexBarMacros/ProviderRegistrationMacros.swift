import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct ProviderDescriptorRegistrationMacro: PeerMacro {
    public static func expansion(
        of _: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in _: some MacroExpansionContext) throws -> [DeclSyntax]
    {
        guard let typeName = Self.typeName(from: declaration) else { return [] }

        let registerName = "_CodexBarDescriptorRegistration_\(typeName)"
        return [
            DeclSyntax(
                "private let \(raw: registerName) = ProviderDescriptorRegistry.register(\(raw: typeName).descriptor)"),
        ]
    }

    private static func typeName(from declaration: some DeclSyntaxProtocol) -> String? {
        if let decl = declaration.as(StructDeclSyntax.self) { return decl.name.text }
        if let decl = declaration.as(ClassDeclSyntax.self) { return decl.name.text }
        if let decl = declaration.as(EnumDeclSyntax.self) { return decl.name.text }
        return nil
    }
}

public struct ProviderImplementationRegistrationMacro: PeerMacro {
    public static func expansion(
        of _: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in _: some MacroExpansionContext) throws -> [DeclSyntax]
    {
        guard let typeName = Self.typeName(from: declaration) else { return [] }

        let registerName = "_CodexBarImplementationRegistration_\(typeName)"
        return [
            DeclSyntax(
                "private let \(raw: registerName) = ProviderImplementationRegistry.register(\(raw: typeName)())"),
        ]
    }

    private static func typeName(from declaration: some DeclSyntaxProtocol) -> String? {
        if let decl = declaration.as(StructDeclSyntax.self) { return decl.name.text }
        if let decl = declaration.as(ClassDeclSyntax.self) { return decl.name.text }
        if let decl = declaration.as(EnumDeclSyntax.self) { return decl.name.text }
        return nil
    }
}

@main
struct CodexBarMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ProviderDescriptorRegistrationMacro.self,
        ProviderImplementationRegistrationMacro.self,
    ]
}
