export class VirtualBufferDisk {
    fileBuffer;

    async load() {

    }

    async write(offset, length, data) {
        this.fileBuffer.set(data.subarray(0, offset), offset)
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
