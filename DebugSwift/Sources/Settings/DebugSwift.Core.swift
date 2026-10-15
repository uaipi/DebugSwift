// The platform-neutral network types live in DebugSwiftCore; re-exporting them keeps
// `import DebugSwift` source compatible for existing hosts. CocoaPods compiles both
// source trees into a single module, so there is nothing to import there.
#if canImport(DebugSwiftCore)
@_exported import DebugSwiftCore
#endif
