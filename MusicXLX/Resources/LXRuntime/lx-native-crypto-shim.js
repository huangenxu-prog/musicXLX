// esbuild alias target for LX 1.9.2's @/utils/nativeModules/crypto import.
// The cryptographic operations themselves are implemented by the native Swift bridge.
const native = globalThis.LXNativeCrypto;

function requireNative() {
  if (!native) throw new Error('LXNativeCrypto bridge is not installed');
  return native;
}

export const AES_MODE = Object.freeze({
  CBC_128_PKCS7Padding: 'AES/CBC/PKCS7Padding',
  // LX 1.9.2 Android passes the literal "AES" to Cipher.getInstance().
  // Android's default provider resolves that to AES/ECB/PKCS5Padding.
  ECB_128_NoPadding: 'AES',
});

export const RSA_PADDING = Object.freeze({
  OAEPWithSHA1AndMGF1Padding: 'RSA/ECB/OAEPWithSHA1AndMGF1Padding',
  NoPadding: 'RSA/ECB/NoPadding',
});

export function aesEncryptSync(text, key, iv, mode) {
  return requireNative().aesEncryptSync(String(text), String(key), String(iv), String(mode));
}

export function aesDecryptSync(text, key, iv, mode) {
  return requireNative().aesDecryptSync(String(text), String(key), String(iv), String(mode));
}

export function rsaEncryptSync(text, key, padding) {
  return requireNative().rsaEncryptSync(String(text), String(key), String(padding));
}

export async function hashSHA1(text) {
  return requireNative().sha1(String(text));
}

// These methods are not used by the extracted catalog dependency graph.
// Fail explicitly instead of silently returning fabricated key material.
export async function generateRsaKey() {
  throw new Error('generateRsaKey is not available in the MusicXLX catalog runtime');
}
export async function rsaEncrypt() {
  throw new Error('Async rsaEncrypt is not available in the MusicXLX catalog runtime');
}
export async function rsaDecrypt() {
  throw new Error('rsaDecrypt is not available in the MusicXLX catalog runtime');
}
export function rsaDecryptSync() {
  throw new Error('rsaDecryptSync is not available in the MusicXLX catalog runtime');
}
export async function aesEncrypt() {
  throw new Error('Async aesEncrypt is not available in the MusicXLX catalog runtime');
}
export async function aesDecrypt() {
  throw new Error('Async aesDecrypt is not available in the MusicXLX catalog runtime');
}
