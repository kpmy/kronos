import { readFile } from 'fs/promises'

export class VirtualDisk {
    filePath;
    fileBuffer;

    constructor(filePath) {
        this.filePath = filePath;
    }

    async load() {
        const buffer = await readFile(this.filePath);
        this.fileBuffer = new Uint8Array(buffer.buffer, buffer.byteOffset, buffer.byteLength);
    }

    async read(offset, length) {
        return this.fileBuffer.subarray(offset, offset + length)
    }

    isMounted() {
        return true;
    }

    setMounted(ok){
        return true
    }
}
