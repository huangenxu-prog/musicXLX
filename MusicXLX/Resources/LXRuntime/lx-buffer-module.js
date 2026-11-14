// esbuild/Metro alias target for LX source imports from "buffer".
// Must be evaluated after lx-buffer.js has installed the global constructor.
const Buffer = globalThis.Buffer;
if (!Buffer) throw new Error("LX Buffer shim was not installed before the provider bundle.");
export { Buffer };
export default { Buffer };
