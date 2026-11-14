(function (global) {
  'use strict';

  // Minimal Node Buffer surface used by the selected LX 1.9.2 catalog modules.
  // This is a Uint8Array-backed compatibility layer, not a complete Node Buffer.
  var alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

  function utf8Encode(value) {
    var encoded = unescape(encodeURIComponent(String(value)));
    var bytes = new Uint8Array(encoded.length);
    for (var i = 0; i < encoded.length; i++) bytes[i] = encoded.charCodeAt(i);
    return bytes;
  }

  function utf8Decode(bytes) {
    var binary = '';
    for (var i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
    try { return decodeURIComponent(escape(binary)); }
    catch (_) { return binary; }
  }

  function decodeBase64(value) {
    var input = String(value).replace(/[^A-Za-z0-9+/=_-]/g, '').replace(/-/g, '+').replace(/_/g, '/');
    var out = [];
    var accumulator = 0;
    var bits = 0;
    for (var i = 0; i < input.length; i++) {
      var ch = input.charAt(i);
      if (ch === '=') break;
      var digit = alphabet.indexOf(ch);
      if (digit < 0) continue;
      accumulator = (accumulator << 6) | digit;
      bits += 6;
      if (bits >= 8) {
        bits -= 8;
        out.push((accumulator >> bits) & 255);
        accumulator &= (1 << bits) - 1;
      }
    }
    return new Uint8Array(out);
  }

  function encodeBase64(bytes) {
    var output = '';
    for (var i = 0; i < bytes.length; i += 3) {
      var a = bytes[i], hasB = i + 1 < bytes.length, hasC = i + 2 < bytes.length;
      var b = hasB ? bytes[i + 1] : 0, c = hasC ? bytes[i + 2] : 0;
      var n = (a << 16) | (b << 8) | c;
      output += alphabet.charAt((n >> 18) & 63);
      output += alphabet.charAt((n >> 12) & 63);
      output += hasB ? alphabet.charAt((n >> 6) & 63) : '=';
      output += hasC ? alphabet.charAt(n & 63) : '=';
    }
    return output;
  }

  function from(value, encoding) {
    if (value instanceof LXBuffer) return new LXBuffer(value);
    if (value instanceof ArrayBuffer) return new LXBuffer(new Uint8Array(value));
    if (ArrayBuffer.isView(value)) return new LXBuffer(new Uint8Array(value.buffer, value.byteOffset, value.byteLength));
    if (Array.isArray(value)) return new LXBuffer(value);
    var text = String(value);
    switch (String(encoding || 'utf8').toLowerCase()) {
      case 'base64': case 'base64url': return new LXBuffer(decodeBase64(text));
      case 'hex': {
        var bytes = [];
        for (var i = 0; i + 1 < text.length; i += 2) {
          var byte = parseInt(text.slice(i, i + 2), 16);
          if (!Number.isFinite(byte)) break;
          bytes.push(byte);
        }
        return new LXBuffer(bytes);
      }
      case 'binary': case 'latin1': case 'ascii': {
        var binary = new Uint8Array(text.length);
        for (var j = 0; j < text.length; j++) binary[j] = text.charCodeAt(j) & 255;
        return new LXBuffer(binary);
      }
      case 'utf8': case 'utf-8': case '': default: return new LXBuffer(utf8Encode(text));
    }
  }

  class LXBuffer extends Uint8Array {
    static from(value, encoding) { return from(value, encoding); }
    static alloc(size, fill) {
      var result = new LXBuffer(Math.max(0, Number(size) || 0));
      if (fill !== undefined) result.fill(typeof fill === 'number' ? fill : Number(fill) || 0);
      return result;
    }
    static concat(list, totalLength) {
      var length = totalLength === undefined ? list.reduce(function (sum, item) { return sum + item.length; }, 0) : totalLength;
      var result = new LXBuffer(length), offset = 0;
      list.forEach(function (item) {
        var part = from(item);
        var count = Math.min(part.length, result.length - offset);
        if (count > 0) result.set(part.subarray(0, count), offset);
        offset += count;
      });
      return result;
    }
    static isBuffer(value) { return value instanceof LXBuffer || !!(value && value._isBuffer === true); }
    get _isBuffer() { return true; }
    toString(encoding, start, end) {
      var bytes = this.subarray(start || 0, end === undefined ? this.length : end);
      switch (String(encoding || 'utf8').toLowerCase()) {
        case 'base64': case 'base64url': return encodeBase64(bytes);
        case 'hex': {
          var hex = '';
          for (var i = 0; i < bytes.length; i++) hex += (bytes[i] < 16 ? '0' : '') + bytes[i].toString(16);
          return hex;
        }
        case 'binary': case 'latin1': case 'ascii': {
          var binary = '';
          for (var j = 0; j < bytes.length; j++) binary += String.fromCharCode(bytes[j]);
          return binary;
        }
        case 'utf8': case 'utf-8': default: return utf8Decode(bytes);
      }
    }
    slice(start, end) { return new LXBuffer(this.subarray(start, end)); }
    subarray(start, end) {
      var view = super.subarray(start, end);
      return new LXBufferView(view.buffer, view.byteOffset, view.byteLength);
    }
  }

  // A view keeps Buffer methods and shares the original byte storage, matching
  // Node Buffer.subarray() semantics used by LX's crypto helpers.
  class LXBufferView extends Uint8Array {
    constructor(buffer, byteOffset, length) { super(buffer, byteOffset, length); }
    get _isBuffer() { return true; }
    toString(encoding, start, end) { return LXBuffer.from(this).toString(encoding, start, end); }
    slice(start, end) { return new LXBuffer(this.subarray(start, end)); }
  }

  global.Buffer = LXBuffer;
  global.LXBuffer = LXBuffer;
})(this);
