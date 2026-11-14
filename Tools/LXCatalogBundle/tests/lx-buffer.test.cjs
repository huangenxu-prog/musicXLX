const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

const shimPath = process.argv[2] || path.resolve(__dirname, '../../../MusicXLX/Resources/LXRuntime/lx-buffer.js');
const sandbox = {};
vm.runInNewContext(fs.readFileSync(shimPath, 'utf8'), sandbox, { filename: shimPath });
const Buffer = sandbox.Buffer;

assert.ok(Buffer, 'Buffer global is installed');
const source = Buffer.from([10, 20, 30, 40]);
const sliced = source.slice(1, 3);
sliced[0] = 99;
assert.equal(source[1], 99, 'Buffer.slice shares the backing store');

const sub = source.subarray(2, 4);
sub[0] = 77;
assert.equal(source[2], 77, 'Buffer.subarray shares the backing store');

const copied = Buffer.from(source);
copied[0] = 1;
assert.notEqual(source[0], copied[0], 'Buffer.from(Buffer) copies bytes');

assert.equal(Buffer.from('48656c6c6f', 'hex').toString(), 'Hello');
assert.equal(Buffer.from('5pel5pys6Kqe', 'base64').toString(), '日本語');
assert.equal(Buffer.from('LX Music', 'utf8').toString('base64'), 'TFggTXVzaWM=');
assert.deepEqual(Array.from(Buffer.concat([Buffer.from([1, 2]), Buffer.from([3])])), [1, 2, 3]);
assert.equal(Buffer.from([4, 5, 6]).indexOf(5), 1);

const longBytes = Uint8Array.from({ length: 8193 }, (_, i) => i & 255);
const longBase64 = Buffer.from(longBytes).toString('base64');
assert.deepEqual(Array.from(Buffer.from(longBase64, 'base64')), Array.from(longBytes));

console.log('LX Buffer compatibility tests passed.');
