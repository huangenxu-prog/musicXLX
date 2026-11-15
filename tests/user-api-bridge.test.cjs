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
    sources: { wy: { type: 'music', actions: ['musicUrl'], qualitys: ['128k'] } },
  })
  const init = events.find(e => e.action === 'init')
  assert.equal(init.data.status, true)
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
  assert.throws(() => sandbox.lx.request('https://example.com/no-callback'), /requires a callback/)
  console.log('iOS JS bridge contract tests passed')
}
main().catch(error => { console.error(error); process.exitCode = 1 })
