const PAGE_SIZE = 65536;

export const IPT = 1; //код прерывания
export const SP = 2;  //указатель на стек выражений (верхний элемент)
export const PC = 3;  //указатель на инструкцию
//export const PCs;  //указатель на предыдущую инструкцию (не регистр)
export const IR = 4;  //инструкция
export const P = 5;  //память процесса
export const L = 6;  //область локальных данных текущей процедуры на стеке
export const G = 7;  //область глобальных данных модуля
export const M = 8;  //маска прерываний
export const H = 9;  //конец процедурного стека
export const S = 10;  //указатель на процедурный стек (верхний элемент)
export const F = 11;  //указатель на начало сегмента кода текущей процедуры
export const CODE = 12; //указатель на инструкцию
export const STACK = 32; //СТЕК


export class VirtualMemory {
    memorySizeBytes;
    totalPages;
    memory8;
    memory32;
    memory;
    memorySize;
    registerBase32;
    reg32;
    outOfRange;

    constructor(memorySizeBytes) {
        this.memorySizeBytes = memorySizeBytes;
        this.memorySize = (memorySizeBytes + 3) / 4;
        this.totalPages = (memorySizeBytes / PAGE_SIZE) + 1;
        this.memory = new WebAssembly.Memory({initial: this.totalPages, maximum: this.totalPages});
        this.memory8 = new Uint8Array(this.memory.buffer)
        this.memory32 = new Uint32Array(this.memory.buffer)
        this.outOfRange = false
        this.registerBase32 = this.memorySize;
        this.reg32 = new Uint32Array(this.memory.buffer, this.memorySizeBytes);
    }

    load8(adr32, offset8) {
        let adr8 = adr32 * 4 + offset8
        if (adr8 >= this.memorySizeBytes) {
            this.outOfRange = true;
            return 0;
        }
        return this.memory8[adr8];
    }

    store8n(offset, length, data) {
        this.memory8.set(data.subarray(0, length), offset);
    }

    setReg(i32, reg) {
        this.reg32[reg] = i32;
    }

    load32(adr32) {
        return this.memory32[adr32]
    }

    store32(adr32, i32) {
        this.memory32[adr32] = i32
    }

    getReg(reg) {
        return this.reg32[reg]
    }

    isOutOfRange() {
        return false; //TODO maybe register, should not be called
    }
}
