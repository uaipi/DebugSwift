//
//  DatabaseFileManager.swift
//  DebugSwift
//
//  Finds the app's SQLite and Realm files for the database browser.
//

import Foundation

final class DatabaseFileManager: @unchecked Sendable {
    static let shared = DatabaseFileManager()
    
    private init() {}
    
    func discoverDatabaseFiles() -> [DatabaseFile] {
        var databaseFiles: [DatabaseFile] = []
        
        // Search in Documents directory
        if let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first {
            databaseFiles.append(contentsOf: findDatabaseFiles(in: documentsPath))
        }
        
        // Search in Library directory
        if let libraryPath = NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true).first {
            databaseFiles.append(contentsOf: findDatabaseFiles(in: libraryPath))
        }
        
        // Search in Application Support directory
        if let appSupportPath = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first {
            databaseFiles.append(contentsOf: findDatabaseFiles(in: appSupportPath))
        }
        
        // Search in Caches directory
        if let cachesPath = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first {
            databaseFiles.append(contentsOf: findDatabaseFiles(in: cachesPath))
        }
        
        DebugSwift.Resources.shared.appGroupIdentifiers.forEach { identifier in
            if let path = DebugSwift.Resources.appGroupContainer(identifier)?.path {
                databaseFiles.append(contentsOf: findDatabaseFiles(in: path))
            }
        }
        
        // Search in tmp directory
        let tmpPath = NSTemporaryDirectory()
        databaseFiles.append(contentsOf: findDatabaseFiles(in: tmpPath))
        
        return deduplicateDatabaseFiles(databaseFiles).sorted {
            if $0.name == $1.name {
                return $0.path < $1.path
            }
            return $0.name < $1.name
        }
    }

    private func deduplicateDatabaseFiles(_ databaseFiles: [DatabaseFile]) -> [DatabaseFile] {
        var seenPaths = Set<String>()

        return databaseFiles.filter { databaseFile in
            let normalizedPath = URL(fileURLWithPath: databaseFile.path).resolvingSymlinksInPath().standardized.path
            return seenPaths.insert(normalizedPath).inserted
        }
    }
    
    private func findDatabaseFiles(in directory: String) -> [DatabaseFile] {
        var files: [DatabaseFile] = []
        let fileManager = FileManager.default
        
        guard let enumerator = fileManager.enumerator(atPath: directory) else { return files }
        
        while let fileName = enumerator.nextObject() as? String {
            let fullPath = (directory as NSString).appendingPathComponent(fileName)
            
            // Check if it's a database file
            if let databaseType = DatabaseType.from(fileName: fileName) {
                if let attributes = try? fileManager.attributesOfItem(atPath: fullPath),
                   let fileSize = attributes[.size] as? Int64 {
                    let databaseFile = DatabaseFile(
                        name: (fileName as NSString).lastPathComponent,
                        path: fullPath,
                        type: databaseType,
                        size: fileSize
                    )
                    files.append(databaseFile)
                }
            }
        }
        
        return files
    }
}

// MARK: - Models

struct DatabaseFile: Equatable {
    let name: String
    let path: String
    let type: DatabaseType
    let size: Int64
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

enum DatabaseType: Hashable {
    case sqlite
    case realm
    case coreData
    
    var displayName: String {
        switch self {
        case .sqlite:
            return "SQLite Database"
        case .realm:
            return "Realm Database"
        case .coreData:
            return "Core Data Database"
        }
    }
    
    static func from(fileName: String) -> DatabaseType? {
        let lowercased = fileName.lowercased()

        if lowercased.contains("datamodel") &&
            (lowercased.hasSuffix(".sqlite") ||
                lowercased.hasSuffix(".sqlite3") ||
                lowercased.hasSuffix(".db") ||
                lowercased.hasSuffix(".sqlitedb")) {
            return .coreData
        }
        
        if lowercased.hasSuffix(".sqlite") ||
           lowercased.hasSuffix(".sqlite3") ||
           lowercased.hasSuffix(".db") ||
           lowercased.hasSuffix(".sqlitedb") ||
           lowercased.hasSuffix(".store") {
            return .sqlite
        } else if lowercased.hasSuffix(".realm") {
            return .realm
        }
        
        return nil
    }
}
