import Foundation
import JavaScriptCore
import Security
import CommonCrypto

/// Implements the synchronous crypto surface used by LX Music 1.9.2 catalog modules.
/// Inputs and outputs intentionally follow the Android CryptoModule contract:
/// AES and RSA input strings are Base64; ciphertext output is unwrapped Base64.
enum LXCatalogCryptoBridge {
    enum BridgeError: LocalizedError {
        case invalidBase64
        case invalidAESMode(String)
        case invalidKey
        case unsupportedRSAAlgorithm
        case cryptoFailure(String)

        var errorDescription: String? {
            switch self {
            case .invalidBase64: return "LX crypto received invalid Base64 data."
            case .invalidAESMode(let mode): return "Unsupported LX AES mode: \(mode)"
            case .invalidKey: return "LX crypto key is invalid."
            case .unsupportedRSAAlgorithm: return "RSA algorithm is not supported by this device."
            case .cryptoFailure(let message): return message
            }
        }
    }

    static func install(in context: JSContext) {
        let aesEncrypt: @convention(block) (String, String, String, String) -> String = {
            text, key, iv, mode in
            (try? aes(input: text, key: key, iv: iv, mode: mode, operation: CCOperation(kCCEncrypt))) ?? ""
        }
        let aesDecrypt: @convention(block) (String, String, String, String) -> String = {
            text, key, iv, mode in
            (try? aes(input: text, key: key, iv: iv, mode: mode, operation: CCOperation(kCCDecrypt))) ?? ""
        }
        let rsaEncrypt: @convention(block) (String, String, String) -> String = {
            text, key, padding in
            (try? rsaEncryptBase64(text, publicKeyBase64: key, padding: padding)) ?? ""
        }
        let sha1: @convention(block) (String) -> String = { text in
            sha1Hex(text)
        }

        let bridge = JSValue(newObjectIn: context)!
        bridge.setObject(aesEncrypt, forKeyedSubscript: "aesEncryptSync" as NSString)
        bridge.setObject(aesDecrypt, forKeyedSubscript: "aesDecryptSync" as NSString)
        bridge.setObject(rsaEncrypt, forKeyedSubscript: "rsaEncryptSync" as NSString)
        bridge.setObject(sha1, forKeyedSubscript: "sha1" as NSString)
        context.setObject(bridge, forKeyedSubscript: "LXNativeCrypto" as NSString)
    }

    private static func aes(
        input: String,
        key keyBase64: String,
        iv ivBase64: String,
        mode: String,
        operation: CCOperation
    ) throws -> String {
        guard let inputData = Data(base64Encoded: input, options: .ignoreUnknownCharacters),
              let key = Data(base64Encoded: keyBase64, options: .ignoreUnknownCharacters) else {
            throw BridgeError.invalidBase64
        }
        guard [kCCKeySizeAES128, kCCKeySizeAES192, kCCKeySizeAES256].contains(key.count) else {
            throw BridgeError.invalidKey
        }

        let isCBC = mode == "AES/CBC/PKCS7Padding"
        let isECB = mode == "AES"
        guard isCBC || isECB else { throw BridgeError.invalidAESMode(mode) }

        var options = CCOptions(kCCOptionPKCS7Padding)
        var ivBytes: [UInt8]? = nil
        if isCBC {
            options |= CCOptions(kCCOptionPKCS7Padding)
            var normalizedIV = [UInt8](repeating: 0, count: kCCBlockSizeAES128)
            if let suppliedIV = Data(base64Encoded: ivBase64, options: .ignoreUnknownCharacters) {
                for (index, byte) in suppliedIV.prefix(kCCBlockSizeAES128).enumerated() {
                    normalizedIV[index] = byte
                }
            }
            ivBytes = normalizedIV
        } else {
            // Android Cipher.getInstance("AES") defaults to AES/ECB/PKCS5Padding.
            options |= CCOptions(kCCOptionECBMode)
        }

        let outputCapacity = inputData.count + kCCBlockSizeAES128
        var output = [UInt8](repeating: 0, count: outputCapacity)
        var moved = 0
        let status: CCCryptorStatus = key.withUnsafeBytes { keyBuffer in
            inputData.withUnsafeBytes { inputBuffer in
                output.withUnsafeMutableBytes { outputBuffer in
                    if let ivBytes {
                        return ivBytes.withUnsafeBytes { ivBuffer in
                            CCCrypt(
                                operation, CCAlgorithm(kCCAlgorithmAES), options,
                                keyBuffer.baseAddress, key.count, ivBuffer.baseAddress,
                                inputBuffer.baseAddress, inputData.count,
                                outputBuffer.baseAddress, outputCapacity, &moved
                            )
                        }
                    }
                    return CCCrypt(
                        operation, CCAlgorithm(kCCAlgorithmAES), options,
                        keyBuffer.baseAddress, key.count, nil,
                        inputBuffer.baseAddress, inputData.count,
                        outputBuffer.baseAddress, outputCapacity, &moved
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw BridgeError.cryptoFailure("CommonCrypto AES failed: \(status)")
        }

        let result = Data(output.prefix(moved))
        if operation == CCOperation(kCCEncrypt) {
            return result.base64EncodedString()
        }
        guard let decoded = String(data: result, encoding: .utf8) else {
            throw BridgeError.cryptoFailure("LX AES plaintext is not valid UTF-8.")
        }
        return decoded
    }

    private static func rsaEncryptBase64(
        _ text: String,
        publicKeyBase64: String,
        padding: String
    ) throws -> String {
        guard let message = Data(base64Encoded: text, options: .ignoreUnknownCharacters),
              let spki = Data(base64Encoded: publicKeyBase64, options: .ignoreUnknownCharacters),
              let pkcs1 = extractRSAPublicKey(fromSubjectPublicKeyInfo: spki) else {
            throw BridgeError.invalidBase64
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic
        ]
        var createError: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(pkcs1 as CFData, attributes as CFDictionary, &createError) else {
            throw BridgeError.cryptoFailure(createError?.takeRetainedValue().localizedDescription ?? "Unable to import RSA public key.")
        }

        let algorithm: SecKeyAlgorithm
        switch padding {
        case "RSA/ECB/NoPadding":
            algorithm = .rsaEncryptionRaw
        case "RSA/ECB/OAEPWithSHA1AndMGF1Padding":
            algorithm = .rsaEncryptionOAEPSHA1
        default:
            throw BridgeError.unsupportedRSAAlgorithm
        }
        guard SecKeyIsAlgorithmSupported(key, .encrypt, algorithm) else {
            throw BridgeError.unsupportedRSAAlgorithm
        }
        var encryptError: Unmanaged<CFError>?
        guard let encrypted = SecKeyCreateEncryptedData(key, algorithm, message as CFData, &encryptError) else {
            throw BridgeError.cryptoFailure(encryptError?.takeRetainedValue().localizedDescription ?? "RSA encryption failed.")
        }
        return (encrypted as Data).base64EncodedString()
    }

    /// Extracts the PKCS#1 RSAPublicKey DER payload from an X.509 SubjectPublicKeyInfo.
    private static func extractRSAPublicKey(fromSubjectPublicKeyInfo data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard let outer = readTLV(bytes, at: 0), outer.tag == 0x30 else { return nil }
        guard let algorithm = readTLV(bytes, at: outer.contentStart), algorithm.tag == 0x30,
              let bitString = readTLV(bytes, at: algorithm.end), bitString.tag == 0x03,
              bitString.contentStart < bitString.end else { return nil }
        // The first BIT STRING content byte is the count of unused bits.
        let keyStart = bitString.contentStart + 1
        guard keyStart < bitString.end else { return nil }
        return Data(bytes[keyStart..<bitString.end])
    }

    private static func readTLV(_ bytes: [UInt8], at offset: Int) -> (tag: UInt8, contentStart: Int, end: Int)? {
        guard offset + 2 <= bytes.count else { return nil }
        let tag = bytes[offset]
        var cursor = offset + 1
        let firstLength = Int(bytes[cursor])
        cursor += 1
        let length: Int
        if firstLength & 0x80 == 0 {
            length = firstLength
        } else {
            let count = firstLength & 0x7f
            guard count > 0, count <= 4, cursor + count <= bytes.count else { return nil }
            var value = 0
            for byte in bytes[cursor..<(cursor + count)] { value = (value << 8) | Int(byte) }
            length = value
            cursor += count
        }
        let end = cursor + length
        guard end <= bytes.count else { return nil }
        return (tag, cursor, end)
    }

    private static func sha1Hex(_ text: String) -> String {
        let digest = Array(text.utf8).withUnsafeBufferPointer { buffer -> [UInt8] in
            var output = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
            _ = CC_SHA1(buffer.baseAddress, CC_LONG(buffer.count), &output)
            return output
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
