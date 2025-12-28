@attached(peer, names: prefixed(_CodexBarDescriptorRegistration_))
public macro ProviderDescriptorRegistration() = #externalMacro(
    module: "CodexBarMacros",
    type: "ProviderDescriptorRegistrationMacro")

@attached(peer, names: prefixed(_CodexBarImplementationRegistration_))
public macro ProviderImplementationRegistration() = #externalMacro(
    module: "CodexBarMacros",
    type: "ProviderImplementationRegistrationMacro")
