// Narrow replacement for the only react-native-quick-base64 export used
// by the selected LX 1.9.2 catalog dependency graph (btoa).
const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

export function btoa(input) {
  const value = String(input);
  let output = '';
  for (let index = 0; index < value.length; index += 3) {
    const a = value.charCodeAt(index);
    const hasB = index + 1 < value.length;
    const hasC = index + 2 < value.length;
    const b = hasB ? value.charCodeAt(index + 1) : 0;
    const c = hasC ? value.charCodeAt(index + 2) : 0;
    if (a > 255 || b > 255 || c > 255) {
      throw new Error('btoa input contains characters outside the Latin1 range');
    }
    output += alphabet[a >> 2];
    output += alphabet[((a & 3) << 4) | (b >> 4)];
    output += hasB ? alphabet[((b & 15) << 2) | (c >> 6)] : '=';
    output += hasC ? alphabet[c & 63] : '=';
  }
  return output;
}
