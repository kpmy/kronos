import { readFile } from 'fs/promises'
import {VirtualBufferDisk} from "./disk-buffer.js";

export class VirtualDisk extends VirtualBufferDisk {
    filePath;


    constructor(filePath) {
        super();
        this.filePath = filePath;
    }

    async load() {
        const buffer = await readFile(this.filePath);
        this.fileBuffer = new Uint8Array(buffer.buffer, buffer.byteOffset, buffer.byteLength);
    }

}
