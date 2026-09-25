//
//  EncryptionService.swift
//  DebugSwift
//
//  Created by DebugSwift on 06/09/25.
//  Copyright © 2025 apple. All rights reserved.
//

import Foundation
import CryptoKit
import Security

public protocol EncryptionServiceProtocol {
    func decrypt(_ data: Data, using key: Data?) -> Data?
    func isEncrypted(_ data: Data) -> Bool
    func getDecryptionKey(for url: URL?) -> Data?
    func registerCustomDecryptor(for urlPattern: String, decryptor: @escaping (Data) -> Data?)
    func customDecrypt(_ data: Data, for url: URL?) -> Data?
}

final class EncryptionService: EncryptionServiceProtocol, @unchecked Sendable {
    static let shared = EncryptionService()
    
    private var decryptionKeys: [String: Data] = [:]
    private var customDecryptors: [String: (Data) -> Data?] = [:]
    private let keyLock = NSLock()
    private let customDecryptorLock = NSLock()
    
    private init() {}
    
    func decrypt(_ data: Data, using key: Data?) -> Data? {
        guard let key, [16, 24, 32].contains(key.count) else { return nil }

        let payload = decodedBase64Payload(data) ?? data
        if let decrypted = decryptAESGCM(payload, key: key) {
            return decrypted
        }

        // Preserve the legacy 16-byte IV path for existing iOS integrations.
        if key.count == 32 { return decryptAES256(payload, key: key) }
        if key.count == 16 { return decryptAES128(payload, key: key) }
        return nil
    }
    
    func isEncrypted(_ data: Data) -> Bool {
        guard data.count > 16 else { return false }
        
        if isJSONData(data) {
            return false
        }
        
        let entropy = calculateEntropy(data.prefix(min(1024, data.count)))
        return entropy > 7.0
    }
    
    func getDecryptionKey(for url: URL?) -> Data? {
        guard let url = url else { return nil }
        
        let urlString = url.absoluteString
        keyLock.lock()
        let registeredKeys = decryptionKeys
        keyLock.unlock()

        for (pattern, key) in registeredKeys {
            let isMatch: Bool
            if let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(urlString.startIndex..<urlString.endIndex, in: urlString)
                isMatch = expression.firstMatch(in: urlString, options: [], range: range) != nil
            } else {
                isMatch = urlString.localizedCaseInsensitiveContains(pattern)
            }
            if isMatch {
                return key
            }
        }
        
        return nil
    }
    
    func registerDecryptionKey(for urlPattern: String, key: Data) {
        keyLock.lock()
        defer { keyLock.unlock() }
        decryptionKeys[urlPattern] = key
    }

    func registeredDecryptionKeyPatterns() -> [String] {
        keyLock.lock()
        defer { keyLock.unlock() }
        return decryptionKeys.keys.sorted()
    }

    func clearDecryptionKeys() {
        keyLock.lock()
        defer { keyLock.unlock() }
        decryptionKeys.removeAll()
    }
    
    func registerCustomDecryptor(for urlPattern: String, decryptor: @escaping (Data) -> Data?) {
        customDecryptorLock.lock()
        defer { customDecryptorLock.unlock() }
        customDecryptors[urlPattern] = decryptor
    }
    
    func customDecrypt(_ data: Data, for url: URL?) -> Data? {
        guard let url = url else { return nil }
        
        let urlString = url.absoluteString
        customDecryptorLock.lock()
        let registeredDecryptors = customDecryptors
        customDecryptorLock.unlock()

        for (pattern, decryptor) in registeredDecryptors {
            if urlString.localizedCaseInsensitiveContains(pattern) {
                return decryptor(data)
            }
        }
        
        return nil
    }
    
    private func decryptAES256(_ data: Data, key: Data) -> Data? {
        guard data.count > 16 else { return nil }
        
        let iv = data.prefix(16)
        let encryptedData = data.suffix(from: 16)
        
        do {
            let symmetricKey = SymmetricKey(data: key)
            let sealedBox = try AES.GCM.SealedBox(combined: Data(iv + encryptedData))
            let decryptedData = try AES.GCM.open(sealedBox, using: symmetricKey)
            return decryptedData
        } catch {
            return decryptAESCBC(encryptedData, key: key, iv: Data(iv))
        }
    }

    private func decryptAESGCM(_ data: Data, key: Data) -> Data? {
        guard data.count >= 28 else { return nil }
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(sealedBox, using: SymmetricKey(data: key))
        } catch {
            return nil
        }
    }

    private func decodedBase64Payload(_ data: Data) -> Data? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines), options: .ignoreUnknownCharacters)
    }
    
    private func decryptAES128(_ data: Data, key: Data) -> Data? {
        guard data.count > 16 else { return nil }
        
        let iv = data.prefix(16)
        let encryptedData = data.suffix(from: 16)
        
        return decryptAESCBC(encryptedData, key: key, iv: Data(iv))
    }
    
    private func decryptAESCBC(_ data: Data, key: Data, iv: Data) -> Data? {
        // Fallback to CryptoKit AES-CBC implementation
        do {
            let symmetricKey = SymmetricKey(data: key)
            let sealedBox = try AES.GCM.SealedBox(combined: iv + data)
            return try AES.GCM.open(sealedBox, using: symmetricKey)
        } catch {
            return nil
        }
    }
    
    private func calculateEntropy(_ data: Data) -> Double {
        var frequencies = [UInt8: Int]()
        
        for byte in data {
            frequencies[byte, default: 0] += 1
        }
        
        let length = Double(data.count)
        var entropy: Double = 0.0
        
        for frequency in frequencies.values {
            let p = Double(frequency) / length
            entropy -= p * log2(p)
        }
        
        return entropy
    }
    
    private func isJSONData(_ data: Data) -> Bool {
        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [])
            return true
        } catch {
            return false
        }
    }
}
