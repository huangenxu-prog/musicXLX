// esbuild alias target for react-native-quick-md5 used by LX Music 1.9.2.
export function stringMd5(value) {
  const native = globalThis.LXNativeCrypto;
  if (!native || typeof native.md5 !== 'function') {
    throw new Error('LXNativeCrypto MD5 bridge is not installed');
  }
  return native.md5(String(value));
}
