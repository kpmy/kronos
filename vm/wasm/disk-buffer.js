export class VirtualBufferDisk {
    fileBuffer;

    async load() {

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

    getSize4Kb() {
        return this.fileBuffer.byteLength / (4 * 1024);
    }
}
