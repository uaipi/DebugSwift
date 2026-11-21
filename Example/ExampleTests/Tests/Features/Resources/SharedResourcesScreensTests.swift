//
//  SharedResourcesScreensTests.swift
//  ExampleTests
//

@_spi(DebugSwiftUI) @testable import DebugSwift
@testable import DebugSwiftUI
import Foundation
import Testing

/// The shared SwiftUI Resources screens read the same operations on iOS as on Android. These check
/// that DebugSwift's iOS answers decode into the models the screens use.
@MainActor
@Suite(.serialized)
struct SharedResourcesScreensTests {
    @Test("Files list the sandbox roots, and a file can be read and deleted, never outside them")
    func files() throws {
        let roots = try DebugResourceClient.fetch("files.list", ["path": ""], as: DebugFileListing.self).get()
        #expect(roots.entries.map(\.name) == ["Documents", "Library", "tmp"])

        let name = "shared-files-\(UUID().uuidString.prefix(8)).txt"
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("tmp").appendingPathComponent(name)
        try "hello from the test".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let listing = try DebugResourceClient.fetch("files.list", ["path": "tmp"], as: DebugFileListing.self).get()
        #expect(listing.entries.contains { $0.name == name && !$0.isDirectory })
        let content = try DebugResourceClient.fetch("files.read", ["path": "tmp/\(name)"], as: DebugFileContent.self).get()
        #expect(content.isText)
        #expect(content.text == "hello from the test")

        #expect((try? DebugResourceClient.fetch("files.list", ["path": "Documents/../../"], as: DebugFileListing.self).get()) == nil)
        #expect((try? DebugResourceClient.fetch("files.delete", ["path": "tmp"], as: DebugFileDeletion.self).get()) == nil)
        for root in ["tmp/.", "Documents/child/..", "tmp/"] {
            #expect((try? DebugResourceClient.fetch("files.delete", ["path": root], as: DebugFileDeletion.self).get()) == nil)
        }
        #expect(FileManager.default.fileExists(atPath: url.path))

        // A name ending in a space is its own file: deleting it leaves the one without the space.
        let spaced = url.appendingPathExtension("bak")
        try "plain".write(to: spaced, atomically: true, encoding: .utf8)
        try "spaced".write(to: URL(fileURLWithPath: spaced.path + " "), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: spaced) }
        let spacedDeletion = try DebugResourceClient.fetch("files.delete", ["path": "tmp/\(name).bak "], as: DebugFileDeletion.self).get()
        #expect(spacedDeletion.ok)
        #expect(FileManager.default.fileExists(atPath: spaced.path))
        #expect(!FileManager.default.fileExists(atPath: spaced.path + " "))

        let deletion = try DebugResourceClient.fetch("files.delete", ["path": "tmp/\(name)"], as: DebugFileDeletion.self).get()
        #expect(deletion.ok)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("A configured App Group is a root of the file browser")
    func appGroups() throws {
        let identifier = "group.debugswift.tests"
        // The test app has no App Group entitlement, so a folder stands in for the container.
        let container = FileManager.default.temporaryDirectory.appendingPathComponent("group-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let lookup = DebugSwift.Resources.appGroupContainer
        DebugSwift.Resources.appGroupContainer = { $0 == identifier ? container : nil }
        DebugSwift.Resources.shared.addAppGroup(identifier)
        defer {
            DebugSwift.Resources.shared.removeAppGroup(identifier)
            DebugSwift.Resources.appGroupContainer = lookup
            try? FileManager.default.removeItem(at: container)
        }
        let name = "shared-group-\(UUID().uuidString.prefix(8)).txt"
        try "from the group".write(to: container.appendingPathComponent(name), atomically: true, encoding: .utf8)

        let roots = try DebugResourceClient.fetch("files.list", ["path": ""], as: DebugFileListing.self).get()
        #expect(roots.entries.map(\.name) == ["Documents", "Library", "tmp", identifier])
        let listing = try DebugResourceClient.fetch("files.list", ["path": identifier], as: DebugFileListing.self).get()
        #expect(listing.entries.contains { $0.name == name })
        let content = try DebugResourceClient.fetch("files.read", ["path": "\(identifier)/\(name)"], as: DebugFileContent.self).get()
        #expect(content.text == "from the group")
        #expect((try? DebugResourceClient.fetch("files.delete", ["path": identifier], as: DebugFileDeletion.self).get()) == nil)
    }

    @Test("A symbolic link can't lead the file browser out of its folder, and deleting a link keeps its target")
    func symbolicLinks() throws {
        let documents = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let tag = UUID().uuidString.prefix(8)
        let outside = documents.appendingPathComponent("outside-\(tag)")
        let folder = documents.appendingPathComponent("folder-\(tag)")
        let inside = documents.appendingPathComponent("inside-\(tag)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "kept".write(to: folder.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: outside, withDestinationURL: Bundle.main.bundleURL)
        try FileManager.default.createSymbolicLink(at: inside, withDestinationURL: folder)
        defer { [outside, inside, folder].forEach { try? FileManager.default.removeItem(at: $0) } }

        let plist = Bundle.main.bundleURL.appendingPathComponent("Info.plist")
        #expect((try? DebugResourceClient.fetch("files.list", ["path": "Documents/outside-\(tag)"], as: DebugFileListing.self).get()) == nil)
        #expect((try? DebugResourceClient.fetch("files.read", ["path": "Documents/outside-\(tag)/Info.plist"], as: DebugFileContent.self).get()) == nil)
        #expect((try? DebugResourceClient.fetch("files.delete", ["path": "Documents/outside-\(tag)/Info.plist"], as: DebugFileDeletion.self).get()) == nil)
        #expect(FileManager.default.fileExists(atPath: plist.path))

        let content = try DebugResourceClient.fetch("files.read", ["path": "Documents/inside-\(tag)/note.txt"], as: DebugFileContent.self).get()
        #expect(content.text == "kept")
        // A link to a folder lists as a folder, and a link to a file reads as that file.
        let documentsListing = try DebugResourceClient.fetch("files.list", ["path": "Documents"], as: DebugFileListing.self).get()
        #expect(documentsListing.entries.first { $0.name == "inside-\(tag)" }?.isDirectory == true)
        let fileLink = documents.appendingPathComponent("note-link-\(tag)")
        try FileManager.default.createSymbolicLink(at: fileLink, withDestinationURL: folder.appendingPathComponent("note.txt"))
        defer { try? FileManager.default.removeItem(at: fileLink) }
        #expect(try DebugResourceClient.fetch("files.read", ["path": "Documents/note-link-\(tag)"], as: DebugFileContent.self).get().text == "kept")
        let deletion = try DebugResourceClient.fetch("files.delete", ["path": "Documents/inside-\(tag)"], as: DebugFileDeletion.self).get()
        #expect(deletion.ok)
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: inside.path)) == nil)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("note.txt").path))
    }

    @Test("Preferences list, save with the key's type, delete, and show changes since a snapshot")
    func preferences() throws {
        let key = "shared-prefs-\(UUID().uuidString.prefix(8))"
        UserDefaults.standard.set(3, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        _ = DebugSwiftRuntime.perform(featureID: "preferences", actionID: "snapshot_preferences")
        let listing = try DebugResourceClient.fetch("prefs.list", as: DebugPreferenceListing.self).get()
        let value = try #require(listing.stores.first?.values.first { $0.key == key })
        #expect(value.type == "Int")
        #expect(value.value == "3")

        #expect(DebugSwiftRuntime.perform(featureID: "preferences", actionID: "set_preference", value: "Standard|\(key)=seven").contains("whole number"))
        _ = DebugSwiftRuntime.perform(featureID: "preferences", actionID: "set_preference", value: "Standard|\(key)=7")
        #expect(UserDefaults.standard.integer(forKey: key) == 7)

        let changes = try DebugResourceClient.fetch("prefs.diff", as: DebugPreferenceChanges.self).get()
        #expect(changes.snapshotAt != nil)
        #expect(changes.changes.contains { $0.key == key && $0.old == "3" && $0.new == "7" })
        _ = DebugSwiftRuntime.perform(featureID: "preferences", actionID: "undo_preference_change", value: key)
        #expect(UserDefaults.standard.integer(forKey: key) == 3)

        _ = DebugSwiftRuntime.perform(featureID: "preferences", actionID: "delete_preference", value: "Standard|\(key)")
        #expect(UserDefaults.standard.object(forKey: key) == nil)
    }

    @Test("A preference key with \"=\" or \"|\" is saved and deleted whole")
    func preferenceKeyDelimiters() {
        let key = "feature=enabled|beta-\(UUID().uuidString.prefix(8))"
        let prefix = String(key.prefix { $0 != "=" })
        UserDefaults.standard.set("on", forKey: key)
        defer { [key, prefix].forEach { UserDefaults.standard.removeObject(forKey: $0) } }
        let saved = DebugSwiftRuntime.perform(
            featureID: "preferences", actionID: "set_preference",
            value: DebugPreferenceEditView.payload(store: "Standard", key: key, value: "off")
        )
        #expect(saved == "Saved \(key).")
        #expect(UserDefaults.standard.string(forKey: key) == "off")
        #expect(UserDefaults.standard.object(forKey: prefix) == nil)
        _ = DebugSwiftRuntime.perform(
            featureID: "preferences", actionID: "delete_preference",
            value: DebugPreferenceEditView.payload(store: "Standard", key: key, value: nil)
        )
        #expect(UserDefaults.standard.object(forKey: key) == nil)
    }

    @Test("Saving an existing key keeps its spaces, and a folder lists all its entries")
    func exactKeysAndLongFolders() throws {
        let key = "shared-prefs-spaced-\(UUID().uuidString.prefix(8)) "
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set("old", forKey: key)
        defer { [key, trimmed].forEach { UserDefaults.standard.removeObject(forKey: $0) } }
        DebugPreferenceEditView(store: "Standard", key: key, type: "String", value: "new").save()
        #expect(UserDefaults.standard.string(forKey: key) == "new")
        #expect(UserDefaults.standard.object(forKey: trimmed) == nil)

        let folder = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("tmp/shared-many-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for index in 0..<520 {
            FileManager.default.createFile(atPath: folder.appendingPathComponent("file-\(index)").path, contents: Data())
        }
        let listing = try DebugResourceClient.fetch("files.list", ["path": "tmp/\(folder.lastPathComponent)"], as: DebugFileListing.self).get()
        #expect(listing.entries.count == 520)
    }

    @Test("A number stored as 0 or 1 stays a number, and a Boolean stays a Boolean")
    func preferenceNumberTypes() throws {
        let number = "shared-prefs-number-\(UUID().uuidString.prefix(8))"
        let flag = "shared-prefs-flag-\(UUID().uuidString.prefix(8))"
        UserDefaults.standard.set(1, forKey: number)
        UserDefaults.standard.set(1.0, forKey: number + "-double")
        UserDefaults.standard.set(true, forKey: flag)
        defer { [number, number + "-double", flag].forEach { UserDefaults.standard.removeObject(forKey: $0) } }
        let values = try #require(try DebugResourceClient.fetch("prefs.list", as: DebugPreferenceListing.self).get().stores.first?.values)
        #expect(values.first { $0.key == number }?.type == "Int")
        #expect(values.first { $0.key == number + "-double" }?.type == "Double")
        #expect(values.first { $0.key == flag }?.type == "Boolean")
        #expect(values.first { $0.key == flag }?.value == "true")
        // The value shown saves back unchanged.
        #expect(DebugSwiftRuntime.perform(featureID: "preferences", actionID: "set_preference", value: "Standard|\(flag)=false") == "Saved \(flag).")
        #expect(UserDefaults.standard.object(forKey: flag) as? Bool == false)
        _ = DebugSwiftRuntime.perform(featureID: "preferences", actionID: "set_preference", value: "Standard|\(number)=2")
        #expect(UserDefaults.standard.integer(forKey: number) == 2)
    }

    @Test("Cookies are grouped by host")
    func cookies() throws {
        let domain = "shared-cookies-\(UUID().uuidString.prefix(6).lowercased()).test"
        let cookie = try #require(HTTPCookie(properties: [.domain: domain, .path: "/", .name: "session", .value: "abc"]))
        HTTPCookieStorage.shared.setCookie(cookie)
        defer { HTTPCookieStorage.shared.deleteCookie(cookie) }
        let listing = try DebugResourceClient.fetch("cookies.list", as: DebugCookieListing.self).get()
        let host = try #require(listing.hosts.first { $0.host == domain })
        #expect(host.cookies.map(\.name) == ["session"])

        // One cookie can be deleted, then all of them.
        let other = try #require(HTTPCookie(properties: [.domain: domain, .path: "/", .name: "theme", .value: "dark"]))
        HTTPCookieStorage.shared.setCookie(other)
        defer { HTTPCookieStorage.shared.deleteCookie(other) }
        let deleted = try DebugResourceClient.fetch("cookies.delete", ["host": domain, "name": "session"], as: DebugActionReply.self).get()
        #expect(deleted.message == "Deleted session.")
        #expect(HTTPCookieStorage.shared.cookies?.contains { $0.domain == domain && $0.name == "session" } == false)
        #expect(HTTPCookieStorage.shared.cookies?.contains { $0.domain == domain && $0.name == "theme" } == true)
        _ = try DebugResourceClient.fetch("cookies.clear", as: DebugActionReply.self).get()
        #expect(HTTPCookieStorage.shared.cookies?.isEmpty == true)
    }

    @Test("A folder inside a root can be deleted with what it holds")
    func folderDeletion() throws {
        let folder = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("tmp/shared-folder-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("inner"), withIntermediateDirectories: true)
        try "x".write(to: folder.appendingPathComponent("inner/file.txt"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(DebugFilesView(path: "tmp/\(folder.lastPathComponent)").isDeletable)
        #expect(!DebugFilesView(path: "tmp").isDeletable)
        let deletion = try DebugResourceClient.fetch("files.delete", ["path": "tmp/\(folder.lastPathComponent)"], as: DebugFileDeletion.self).get()
        #expect(deletion.ok)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }
}
