import {VirtualBufferDisk} from "./disk-buffer.js";

async function fileToUint8Array(fileOrBlob) {
    // Получаем ArrayBuffer из объекта File или Blob
    const arrayBuffer = await fileOrBlob.arrayBuffer();
    // Возвращаем типизированный массив байт
    return new Uint8Array(arrayBuffer);
}

export class VirtualWebDisk extends VirtualBufferDisk {

    blob

    constructor(blob) {
        super();
        this.blob = blob;
    }

    async load() {
        this.fileBuffer = await fileToUint8Array(this.blob)
    }


}
