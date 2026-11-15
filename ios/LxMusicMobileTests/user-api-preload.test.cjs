'use strict'

const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const vm = require('node:vm')

const preloadPath = path.join(__dirname, '..', 'LxMusicMobile', 'user-api-preload.js')
const source = fs.readFileSync(preloadPath, 'utf8')
const sandbox = {
  console,
  __lx_native_call__: () => {},
  __lx_native_call__set_timeout: () => {},
  __lx_native_call__utils_str2b64: value => Buffer.from(value, 'utf8').toString('base64'),
  __lx_native_call__utils_b642buf: value => JSON.stringify(Array.from(Buffer.from(value, 'base64'))),
  __lx_native_call__utils_buf2b64: values => Buffer.from(values).toString('base64'),
  __lx_native_call__utils_str2md5: value => require('node:crypto').createHash('md5').update(decodeURIComponent(value)).digest('hex'),
  __lx_native_call__utils_random_bytes: size => JSON.stringify(Array.from({ length: size }, (_, index) => index & 0xff)),
  __lx_native_call__utils_aes_encrypt: () => '',
  __lx_native_call__utils_rsa_encrypt: () => '',
}

vm.createContext(sandbox)
vm.runInContext(source, sandbox, { filename: 'user-api-preload.js' })
sandbox.lx_setup('test-runtime-key', 'test-id', 'Test', '', '1', 'CI', '', '')
const buffer = sandbox.lx.utils.buffer

const emojiBytes = buffer.from('😀')
assert.equal(buffer.bufToString(emojiBytes, 'hex'), 'f09f9880')
assert.equal(buffer.bufToString(new Uint8Array([0xf0, 0x9f, 0x98, 0x80]), 'utf8'), '😀')
assert.equal(buffer.bufToString(new Uint8Array([0x41, 0xff, 0x42]), 'utf8'), 'A�B')

const binary = new Uint8Array([0x00, 0xff, 0x80, 0x41, 0x10])
const encoded = buffer.bufToString(binary, 'base64')
assert.equal(encoded, 'AP+AQRA=')
assert.deepEqual(Array.from(buffer.from(encoded, 'base64')), Array.from(binary))

assert.equal(sandbox.lx.utils.crypto.randomBytes(8).length, 8)
assert.throws(() => sandbox.lx.utils.crypto.randomBytes(-1), error => error && error.name === 'RangeError')
assert.throws(() => sandbox.lx.utils.crypto.randomBytes(1048577), error => error && error.name === 'RangeError')

console.log('user-api-preload runtime tests passed')
