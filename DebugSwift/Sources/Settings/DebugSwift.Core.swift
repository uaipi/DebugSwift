// The platform-neutral network types live in DebugSwiftCore; re-exporting them keeps
// `import DebugSwift` source compatible for existing hosts. CocoaPods compiles both source
// trees into a single module, so there is nothing to import there. `canImport` is not used
// because Xcode 27's explicit modules do not report package dependencies through it.
#if SWIFT_PACKAGE
@_exported import DebugSwiftCore
#endif
