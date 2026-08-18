# PrivilegedHelper

Executable target for the `SMAppService` privileged helper, implementing
`PrivilegedHelperXPC.PrivilegedHelperProtocol` (see
`Packages/PrivilegedHelperXPC`). Not yet scaffolded — planned once the
Developer ID app target exists to register it.

Only used by the Developer ID build; the App Store build never installs or
references this helper.
