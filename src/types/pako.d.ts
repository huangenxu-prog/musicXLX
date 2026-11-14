declare module 'pako' {
  export function gzip(data: Uint8Array | string): Uint8Array
  export function ungzip(data: Uint8Array | string): Uint8Array

  const pako: {
    gzip: typeof gzip
    ungzip: typeof ungzip
  }

  export default pako
}
