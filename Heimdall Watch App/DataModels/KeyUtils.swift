//
//  KeyUtils.swift
//  Heimdall Watch App
//
//  Created by 叶浩宁 on 2024-04-26.
//

import Foundation
import CryptoKit

public typealias TyPrvKey = P256.Signing.PrivateKey
public typealias TyPubKey = P256.Signing.PublicKey
// we only allow a single key for this app
let label = "com.haoningye.Heimdall.watchkitapp"
let tag = "Heimdall's Key"


// https://developer.apple.com/documentation/cryptokit/storing_cryptokit_keys_in_the_keychain
func loadKey() -> (TyPrvKey, String)? {
    // Seek an elliptic-curve key with a given label.
    let queryRetrieve = [kSecClass: kSecClassKey,
          kSecAttrApplicationLabel: label,
            kSecAttrApplicationTag: tag,
                   kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
     kSecUseDataProtectionKeychain: true,
                     kSecReturnRef: true] as [String: Any]
    
    
    // Find and cast the result as a SecKey instance.
    var item: CFTypeRef?
    var secKeyRead: SecKey
    switch SecItemCopyMatching(queryRetrieve as CFDictionary, &item) {
    case errSecSuccess: secKeyRead = item as! SecKey
    case errSecItemNotFound:
        print("Item Not Found")
        return nil
    case let status: fatalError("Keychain read failed: \(status.description)")
    }
    // Convert the SecKey into a CryptoKit key.
    var error: Unmanaged<CFError>?
    guard let data = SecKeyCopyExternalRepresentation(secKeyRead, &error) as Data? else {
        fatalError("Error while converting back to CryptoKit: \(error.debugDescription)")
    }
    let keyRetrieved = try! TyPrvKey(x963Representation: data)
    
    return (keyRetrieved, dumpKey(prvKey: secKeyRead))
}

func storeKey() {
    guard (loadKey() == nil) else {
        print("the key exist, skipping...")
        return
    }
    let privatekey = TyPrvKey()
    let attributes = [kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
                     kSecAttrKeyClass: kSecAttrKeyClassPrivate] as [String: Any]
    
    guard let secKey = SecKeyCreateWithData(privatekey.x963Representation as CFData,
                                            attributes as CFDictionary,
                                            nil)
    else {
        fatalError("Unable to create SecKey representation.")
    }
    let query = [kSecClass: kSecClassKey,
  kSecAttrApplicationLabel: label,
    kSecAttrApplicationTag: tag,
        kSecAttrAccessible: kSecAttrAccessibleWhenUnlocked,
kSecUseDataProtectionKeychain: true,
              kSecValueRef: secKey] as [String: Any]
    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else {
        fatalError("Unable to store item: \(status)=>\(String(describing: SecCopyErrorMessageString(status, nil)))")
    }
}

func deleteKey() {
    let queryRetrieve = [kSecClass: kSecClassKey,
          kSecAttrApplicationLabel: label,
            kSecAttrApplicationTag: tag,
                   kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
     kSecUseDataProtectionKeychain: true,
                     kSecReturnRef: true] as [String: Any]
    SecItemDelete(queryRetrieve as CFDictionary)
}

private func dumpKey(prvKey: SecKey) -> String {
    return String(toSSHPublicKey( k: SecKeyCopyPublicKey(prvKey)!, comment: "I am comment"))
}


// the Following is for dump key so that you can add to .ssh/authorized_keys
//https://raw.githubusercontent.com/migueldeicaza/SwiftTermApp/4eb16902e47161bd64c102b0e20d1eae8780b633/SwiftTermApp/Keys/SshUtil.swift
func encode (str: String) -> Data {
    guard let utf8 = str.data(using: .utf8) else {
        return Data()
    }
    return encode (utf8.count) + utf8
}
func encode (data: Data) -> Data {
    return encode (data.count) + data
}
func encode (_ int: Int) -> Data {
    var bigEndianInt = Int32 (int).bigEndian
    return Data (bytes: &bigEndianInt, count: 4)
}

func toSSHPublicKey(k: SecKey, comment: String) -> String {
    let data = SecKeyCopyExternalRepresentation (k, nil)! as Data
    let inner = (encode (str: "ecdsa-sha2-nistp256") + encode (str: "nistp256") + encode (data: data)).base64EncodedString()
    return "ecdsa-sha2-nistp256 \(inner) \(comment)"
}
