// Run: node tests/user-api-bridge.test.cjs
// Offline contract tests for the iOS JavaScriptCore preload bridge.
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const vm = require('node:vm')
const preload = fs.readFileSync(path.join(__dirname, '../ios/LxMusicMobile/user-api-preload.js'), 'utf8')
const events = []
const sandbox = {
  console,
  __lx_native_call__(key, action, data) { events.push({ key, action, data: JSON.parse(data) }) },
  __lx_native_call__set_timeout() {},
  __lx_native_call__clear_timeout() {},
  __lx_native_call__utils_str2b64() { return '' },
  __lx_native_call__utils_b642buf() { return '[]' },
  __lx_native_call__utils_buf2b64() { return '' },
  __lx_native_call__utils_str2md5() { return '' },
  __lx_native_call__utils_random_bytes() { return '[]' },
  __lx_native_call__utils_aes_encrypt() { return '' },
  __lx_native_call__utils_rsa_encrypt() { return '' },
}
sandbox.globalThis = sandbox
vm.createContext(sandbox)
vm.runInContext(preload, sandbox, { filename: 'user-api-preload.js' })
sandbox.lx_setup('test-key', 'test-id', 'test', '', '1', '', '', '')
assert.equal(typeof sandbox.lx.request, 'function')
async function main() {
  await sandbox.lx.send(sandbox.lx.EVENT_NAMES.inited, {
    sources: { wy: { type: 'music', actions: ['musicUrl'], qualitys: ['128k'] }, xm: { type: 'music', actions: ['musicUrl'], qualitys: ['128k'] } },
  })
  const init = events.find(e => e.action === 'init')
  assert.equal(init.data.status, true)
  assert.deepEqual(Array.from(Object.keys(init.data.info.sources)).sort(), ['wy', 'xm'])
  assert.deepEqual(Array.from(init.data.info.sources.xm.actions), ['musicUrl'])
  await sandbox.lx.on(sandbox.lx.EVENT_NAMES.request, ({ action }) => {
    assert.equal(action, 'musicUrl')
    return 'https://example.com/audio.mp3'
  })
  sandbox.__lx_native__('test-key', 'request', JSON.stringify({
    requestKey: 'song-1',
    data: { source: 'wy', action: 'musicUrl', info: { type: '128k', musicInfo: {} } },
  }))
  await new Promise(resolve => setImmediate(resolve))
  const resolved = events.find(e => e.action === 'response' && e.data.requestKey === 'song-1')
  assert.equal(resolved.data.status, true)
  assert.equal(resolved.data.result.data.url, 'https://example.com/audio.mp3')
  let callbackBody
  sandbox.lx.request('https://example.com/api', {}, (error, response, body) => {
    assert.equal(error, null)
    callbackBody = body
    assert.equal(response.statusCode, 200)
  })
  const request = events.find(e => e.action === 'request')
  assert.equal(request.data.url, 'https://example.com/api')
  sandbox.__lx_native__('test-key', 'response', JSON.stringify({
    requestKey: request.data.requestKey,
    error: null,
    response: { statusCode: 200, statusMessage: 'OK', headers: {}, body: { ok: true } },
  }))
  assert.equal(callbackBody.ok, true)
  // Two-argument form is used by some community source scripts.
  let shortCallbackBody
  sandbox.lx.request('https://example.com/short', (error, response, body) => {
    assert.equal(error, null)
    assert.equal(response.statusCode, 200)
    shortCallbackBody = body
  })
  const shortRequest = events.filter(e => e.action === 'request').at(-1)
  assert.equal(shortRequest.data.url, 'https://example.com/short')
  sandbox.__lx_native__('test-key', 'response', JSON.stringify({
    requestKey: shortRequest.data.requestKey,
    error: null,
    response: { statusCode: 200, statusMessage: 'OK', headers: {}, body: 'ok' },
  }))
  assert.equal(shortCallbackBody, 'ok')
  // Binary responses must survive JSON transport and arrive as Uint8Array,
  // not an object with numeric keys or an untyped JSON array.
  let binaryBody
  sandbox.lx.request('https://example.com/binary', { binary: true }, (error, response, body) => {
    assert.equal(error, null)
    binaryBody = body
    assert.equal(response.body, body)
  })
  const binaryRequest = events.filter(e => e.action === 'request').at(-1)
  assert.equal(binaryRequest.data.options.binary, true)
  sandbox.__lx_native__('test-key', 'response', JSON.stringify({
    requestKey: binaryRequest.data.requestKey,
    error: null,
    response: { statusCode: 200, statusMessage: 'OK', headers: {}, body: [0, 255, 128, 65] },
  }))
  assert.equal(Object.prototype.toString.call(binaryBody), '[object Uint8Array]')
  assert.deepEqual(Array.from(binaryBody), [0, 255, 128, 65])
  assert.throws(() => sandbox.lx.request('https://example.com/no-callback'), /requires a callback/)
  // Cancellation must be safe when the source invokes its abort handle twice.
  let cancelledCallbackCount = 0
  const abort = sandbox.lx.request('https://example.com/cancel', () => {
    cancelledCallbackCount++
  })
  const pending = events.filter(e => e.action === 'request').at(-1)
  abort()
  abort()
  const cancels = events.filter(e => e.action === 'cancelRequest' && e.data === pending.data.requestKey)
  assert.equal(cancels.length, 1)
  sandbox.__lx_native__('test-key', 'response', JSON.stringify({
    requestKey: pending.data.requestKey,
    error: 'request canceled',
    response: null,
  }))
  assert.equal(cancelledCallbackCount, 0)
  console.log('iOS JS bridge contract tests passed')
}
main().catch(error => { console.error(error); process.exitCode = 1 })
