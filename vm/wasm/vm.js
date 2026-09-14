import wabt from "wabt";
import {VirtualMemory, IPT, P, H, IR, F, G, PC, S, SP, M, L, CODE, STACK} from './mem.js'
import {readFile, stat} from 'fs/promises'
import * as path from "node:path";
import {VirtualSerial} from "./serial.js";
import * as fs from "node:fs/promises";
import * as readline from "node:readline";
const AStackSize = 15

export class VirtualMachine {
    memory
    disks
    wabt
    vm
    stepIdx
    diskOpLater
    trace
    bTimer
    bTimerDescr

    constructor(memorySizeBytes, console) {
        this.disks = [];
        this.memory = new VirtualMemory(memorySizeBytes);
        this.console = console;
        this.serial = new VirtualSerial();
        this.diskOpLater = [];
        this.trace = [];
        this.bTimer = false;
    }

    getMemory() {
        return this.memory;
    }

    addDisk(disk) {
        this.disks.push(disk);
    }

    getDiskCount() {
        return this.disks.length;
    }

    getDisk(diskIdx) {
        return this.disks[diskIdx];
    }

    async loadTrace() {
        let trace = [];
        if (process.env.KRONOS_TRACE) {
            try {
                await stat(process.env.KRONOS_TRACE);
                const file = await fs.open(process.env.KRONOS_TRACE, 'r');
                const rl = readline.createInterface({
                    input: file.createReadStream(),
                    crlfDelay: Infinity
                });
                let minStep = Number.MAX_VALUE;
                for await (const line of rl) {
                    if (line.startsWith("Step =")){
                        let lineRet = {}
                        let lineValues = line.split(", ")
                        for (let lineValue of lineValues){
                            let lv = lineValue.split(" = ")
                            if (lv[0] === "PC" || lv[0] === "IR") {
                                lineRet[lv[0]] = parseInt(lv[1], 16)
                            } else {
                                lineRet[lv[0]] = parseInt(lv[1])
                            }
                        }
                        trace.push(lineRet);
                        minStep = Math.min(lineRet['Step'], minStep);
                    }
                }
                console.log(`loaded ${trace.length} traces starting from ${minStep}`);
                for (let missedStep = 0; missedStep < minStep; missedStep++) {
                    trace.unshift(null);
                }
            } catch (e) {
                throw e;
            }
        }
        return trace;
    }

    async runSafe() {
        try {
            await this.run()
        } catch (e) {
            clearInterval(this.bTimerDescr)
            console.error(e);
        }
    }

    async run() {
        this.trace = await this.loadTrace();
        this.wabt = await wabt();
        await this.start()
        let badIrq = false;
        while (!badIrq) {
            badIrq = await this.step()
            for (let op of this.diskOpLater) {
                await op();
            }
            this.diskOpLater.splice(0, this.diskOpLater.length);
            if(!badIrq) {
                this.checkTrace()
                this.clearStack()
            }
        }
        this.stop();
    }

    checkTrace() {
        if (this.trace.length === 0) {
            return
        }
        let stepTrace = this.trace.shift()
        if (stepTrace == null) {
            return;
        }
        if (stepTrace['Step'] != this.stepIdx - 1) {
            debugger
        }
        if (stepTrace['IR'] != this.memory.getReg(IR)){
            debugger
        }
    }

    irq() {
        let ipt = this.memory.getReg(IPT)
        let m = this.memory.getReg(M)
        if (ipt === 0) {
            if (this.memory.isOutOfRange())
                ipt = 3;
            else if (this.bTimer)
            {
                if ((m & 0x2) !== 0)
                {
                    this.bTimer = false;
                    ipt = 1; // timer ipt
                }
            }
            else if ((m & 0x1) !== 0)
            {
                //SIO *s = sios.inpReady();

                // if (s != NULL)
                //     Ipt = s->ipt();
                // else
                // {
                //     s = sios.outReady();
                //     if (s != NULL)
                //         Ipt = s->ipt() + 1;
                // }
                if (this.console.isInpIptEnabled()) {
                    ipt = this.console.getIpt();
                } else if (this.console.isOutIptEnabled()) {
                    ipt = this.console.getIpt() + 1;
                }
            }
        }
        if (ipt !== 0) {
            this.trap(ipt)
            ipt = 0;
        }
        this.memory.setReg(ipt, IPT)
        return true;
    }

    trap(no) {
        if (no === 7)
            this.bDebug = true;

        if (no >= 0x3F)
        {
            this.memory.store32(this.memory.getReg(P) + 6,  no);
            no = 0x3F;
        }
        if (no === 0)
        {
            this.trap(6);
            return;
        }
        let m = this.memory.getReg(M);
        if (no >= 0xC && no < 0x3F && (m & 0x1) === 0)
            return;
        if (no >= 2 && no < 0xC)
        {
            this.memory.store32(this.memory.getReg(P) + 6,  no);
            if ((m & Number(BigInt.asIntN(32, 1n << BigInt(no) & 0xFFFFFFFFn))) === 0)
            {
                if (no !== 3) // booter use Ipt 3 to determine memory size
                {
                    //log.error("Unexpected interrupt {}.\n", no);
                    this.bDebug = true;
                }
                return;
            }
        }
        if (no === 1  && (m & 0x2) === 0)
            return;
        if (no === 0x3F && (m & (1 << 31)) === 0)
            return;
        this.transfer(no * 2, this.memory.load32(no * 2 + 1));
    }

    transfer(p_to, p_from) {
        let i = this.memory.load32(p_to);
        this.memory.store32(p_from, this.memory.getReg(P));
        this.saveRegisters();
        this.memory.setReg(i, P);
        this.restoreRegisters();
    }

    async step() {
        if(!this.irq())
            return true;
        let pcs = this.memory.getReg(PC);
        this.memory.setReg(this.memory.load8(this.memory.getReg(CODE), pcs), IR)
        this.memory.setReg(pcs + 1, PC)
        let ir = this.memory.getReg(IR);
        let irCode = ir.toString(16).toUpperCase();
        let irName = IR_MAP[irCode];
        let irFunc = this.vm[`ir_${irName}`];
        try {
            irFunc();
        } catch (e) {
            console.error(this.stepIdx, irCode, irName, e);
            this.memory.setReg(0x7, IPT)
            return true;
        }
        if (this.memory.getReg(IPT) === 0 && this.memory.getReg(S) > this.memory.getReg(H) || this.memory.getReg(S) === 0) {
            throw 'out of stack';
        }
        this.stepIdx++;
        return false
    }

    clearStack() {
        // 1. Получаем текущий индекс вершины стека выражений (sp)
        const sp = this.memory.getReg(SP);

        // 2. Пробегаемся циклом от текущего sp до максимального размера AStackSize
        for (let t = sp; t < AStackSize; t++) {
            // 3. Зануляем ячейку в WebAssembly.Memory по гостевому индексу (STACK + t)
            this.memory.setReg(0, STACK + t);
        }
    }

    stop() {
        clearInterval(this.bTimerDescr)
        this.saveRegisters()
    }

    async start() {
        this.stepIdx = 0;
        this.memory.setReg(0, IPT)
        this.memory.setReg(0, SP)
        this.memory.setReg(this.memory.load32(1), P)
        this.restoreRegisters()

        const wastCode = await readFile(path.join(process.cwd(), 'core.wat'), 'utf-8')
        const parsedModule = this.wabt.parseWat('core.wat', wastCode);
        const { buffer } = parsedModule.toBinary({ log: true, canonicalize_lebs: true });
        let that = this;
        const wasmModule = await WebAssembly.compile(buffer);
        const wasmInstance = await WebAssembly.instantiate(wasmModule, {
            env: {
                memory: this.memory.memory,
                log_debug: function (id, value) {
                    const hexVal = "0x" + (value >>> 0).toString(16).toUpperCase();
                    console.log(`   [Wasm Debug ${id}] output: ${hexVal}`);
                },
                io_host_call: function(port) {
                    //console.log(`[JS Host I/O] Вызвана инструкция IO. Номер порта: ${port}`);
                    // Сюда добавим логику взаимодействия со стеком/памятью, когда она прояснится
                    that.io(port)
                },
                tra_host_call: function(p_to, p_from) {
                    that.transfer(p_to, p_from);
                },
                sys_print_hex: function(value) {
                    // Превращаем в беззнаковый хекс, дополняем нулями до 8 знаков и переводим в верхний регистр
                    const hexStr = (value >>> 0).toString(16).toUpperCase().padStart(8, '0');
                    console.log(`\n${hexStr}`);
                },
                save_stack_host_call: function() {
                    // Вызываем ваш мигрированный метод saveStack из Java
                    that.saveStack();
                },
                restore_stack_host_call: function() {
                    // Вызываем ваш мигрированный метод restoreStack из Java
                    that.restoreStack();
                }
            }});

        this.vm = wasmInstance.exports;
        this.vm.init_vm(this.memory.totalPages, AStackSize)
        this.bTimerDescr = setInterval(() => {
            //this.bTimer = true;
        }, 100)
    }

    saveRegisters() {
        this.memory.store32(1, this.memory.getReg(P))
        this.saveStack();
        this.memory.store32(this.memory.getReg(P), this.memory.getReg(G))
        this.memory.store32(this.memory.getReg(P) + 1, this.memory.getReg(L))
        this.memory.store32(this.memory.getReg(P) + 2, this.memory.getReg(PC))
        this.memory.store32(this.memory.getReg(P) + 3, this.memory.getReg(M))
        this.memory.store32(this.memory.getReg(P) + 4, this.memory.getReg(S))
    }

    restoreRegisters() {
        this.memory.store32(0, this.memory.getReg(P))
        this.memory.setReg(this.memory.load32(this.memory.getReg(P)), G)
        this.memory.setReg(this.memory.load32(this.memory.getReg(G)), F)
        this.memory.setReg(this.memory.getReg(F), CODE)
        this.memory.setReg(this.memory.load32(this.memory.getReg(P) + 1), L)
        this.memory.setReg(this.memory.load32(this.memory.getReg(P) + 2), PC)
        this.memory.setReg(this.memory.load32(this.memory.getReg(P) + 3), M)
        this.memory.setReg(this.memory.load32(this.memory.getReg(P) + 4), S)
        this.memory.setReg(this.memory.load32(this.memory.getReg(P) + 5), H)
        this.memory.setReg(this.memory.getReg(H) - (AStackSize + 1), H)
        this.restoreStack()
    }

    saveStack() {
        let i = this.memory.getReg(S);
        while (this.memory.getReg(SP) !== 0) {
            let s = this.memory.getReg(S)
            this.memory.store32(s, this.pop());
            this.memory.setReg(s + 1, S)
        }
        this.memory.store32(this.memory.getReg(S),  this.memory.getReg(S) - i);
        this.memory.setReg(this.memory.getReg(S) + 1, S);
    }

    restoreStack() {
        this.memory.setReg(this.memory.getReg(S) - 1, S)
        let i = this.memory.load32(this.memory.getReg(S))
        if (i > AStackSize) {
            this.memory.setReg(0x4C, IPT)
            i = AStackSize
        }
        while (i-- > 0) {
            this.memory.setReg(this.memory.getReg(S) - 1, S)
            this.push(this.memory.load32(this.memory.getReg(S)))
        }
    }

    push(i32) {
        let sp = this.memory.getReg(SP)
        if (sp >= 0 && sp < AStackSize) {
            this.memory.setReg(i32, STACK + sp)
            this.memory.setReg(sp + 1, SP)
        } else {
            this.memory.setReg(0x4C, IPT)
        }
    }

    pop() {
        let sp = this.memory.getReg(SP);
        if (sp > 0) {
            sp = sp - 1; // Сначала уменьшаем индекс (аналог --sp)
            let val = this.memory.getReg(STACK + sp); // Читаем правильный верхний элемент
            this.memory.setReg(sp, SP); // Сохраняем новый уменьшенный SP
            return val;
        }
        this.memory.setReg(0x4C, IPT);
        return 0;
    }

    io(no) {
        switch (no) {
            case 0x0: { //input
                let adr = this.pop();
                let ioAddr = adr & 0xFFC;
                if (ioAddr === this.console.getAddress()) { // console ipt 0x0C
                    this.push(this.console.inp(adr));
                } else {
                    let inp = this.serial.inp(no, ioAddr, adr);
                    if (inp != null) {
                        this.push(inp);
                    } else {
                        this.memory.setReg(3, IPT);
                        this.push(0);
                    }
                    //throw new NotImplementedException(String.format("in %x %x", no, ioAddr));
                }
                break;
            }
            case 0x1: { //output
                let i = this.pop();
                let adr = this.pop();
                let ioAddr = adr & 0xFFC;
                if (ioAddr === this.console.getAddress()) {
                    this.console.out(adr, i);
                } else {
                    this.serial.out(no, ioAddr, adr, i);
                    //throw new NotImplementedException(String.format("out %x %x", no, ioAddr));
                }
                break;
            }
            case 0x2: { //disk io
                let len = this.pop();    // bytes
                let adr = this.pop();    // address
                let sec = this.pop();    // sector
                let dsk = this.pop();    // disk
                let op = this.pop();    // operation
                this.diskOpLater.push(async () => {
                    let ret = await this.doDiskOperation(op, dsk, sec, adr, len);
                    this.push(ret);
                })
                break;
            }
            case 0x3: {
                console.log("no io3", this.pop());
                break;
            }
            case 0x4: {
                this.memory.setReg(7, IPT);
                let pc = this.memory.getReg(PC);
                this.memory.setReg(pc - 2, PC);
                break;
            }
            default:
                console.log("unsupported i/o function", String.format("%03X", no));
                this.memory.setReg(7, IPT);
                let pc = this.memory.getReg(PC);
                this.memory.setReg(pc - 2, PC);
            //break;
            //throw new NotImplementedException(String.format("unknown io channel %x", no));
        }
    }

    async doDiskOperation(op, dsk, sec, adr, len) {
        switch (op)
        {
        case 1:
            if (dsk >= 0 && dsk < this.disks.length) {
                if (this.disks[dsk].isMounted()){
                    //do nothing
                }
                this.disks[dsk].setMounted(true);
                return 1;
            }
            return 0;
        case 2:
            if (dsk >= 0 && dsk < this.disks.length) {
                if (!this.disks.get[dsk].isMounted()){
                    //do nothing
                }
                this.disks[dsk].setMounted(false);
                return 1;
            }
            return 0;
        case 3:
            if (dsk >= 0 && dsk < this.disks.length) {
                this.memory.store32(adr, this.disks[dsk].getSize4Kb());
                return 1;
            }
            return 0;
        case 4:
            if (dsk >= 0 && dsk < this.disks.length) {
                let data = await this.disks[dsk].read(sec * 512, len);
                this.memory.store8n(adr * 4, len, data)
                return data.length === len ? 1 : 0;
            }
            return 0;
        case 5:
            if (dsk >= 0 && dsk < this.disks.length) {
                //return Disks.Write(dsk, sec, &mem[adr], len);
            }
            throw "io write not implemented";
            //return 0;
        case 6: {
            const now = new Date();
            this.memory.store32(adr++, now.getFullYear());        // year (e.g., 2025)
            this.memory.store32(adr++, now.getMonth() + 1);       // month 1–12 (JS months are 0‑based)
            this.memory.store32(adr++, now.getDate());            // day of month 1–31
            this.memory.store32(adr++, now.getHours());           // hour 0–23
            this.memory.store32(adr++, now.getMinutes());         // minute 0–59
            this.memory.store32(adr++, now.getSeconds());         // second 0–59

            return 1;
        }
        case 8: // getspecs
            if (dsk >= 0 && dsk < this.disks.length) {
                //var p_spec = pmem(adr);
                //p_spec.setValues(disks.get(dsk).getSpecs().asBytes());

            }
            return 0;
        case 9: // setspecs
            if (dsk >= 0 && dsk < this.disks.length) {

            }
            //throw new NotImplementedException();
            return 1;
            //return Disks.SetSpecs(dsk, (Request*)(byte*)&mem[adr]);
        default:
            //trace("invalid disk operation: %d\n", op);
            //throw new NotImplementedException();
            return 0;
        }
    }
}

const IR_MAP = {
    "0": "LI0",
    "1": "LI1",
    "2": "LI2",
    "3": "LI3",
    "4": "LI4",
    "5": "LI5",
    "6": "LI6",
    "7": "LI7",
    "8": "LI8",
    "9": "LI9",
    "10": "LIB",
    "11": "LID",
    "12": "LIW",
    "13": "LIN",
    "14": "LLA",
    "15": "LGA",
    "16": "LSA",
    "17": "LEA",
    "18": "JFLC",
    "19": "JFL",
    "20": "LLW",
    "21": "LGW",
    "22": "LEW",
    "23": "LSW",
    "24": "LLW4",
    "25": "LLW5",
    "26": "LLW6",
    "27": "LLW7",
    "28": "LLW8",
    "29": "LLW9",
    "30": "SLW",
    "31": "SGW",
    "32": "SEW",
    "33": "SSW",
    "34": "SLW4",
    "35": "SLW5",
    "36": "SLW6",
    "37": "SLW7",
    "38": "SLW8",
    "39": "SLW9",
    "40": "LXB",
    "41": "LXW",
    "42": "LGW2",
    "43": "LGW3",
    "44": "LGW4",
    "45": "LGW5",
    "46": "LGW6",
    "47": "LGW7",
    "48": "LGW8",
    "49": "LGW9",
    "50": "SXB",
    "51": "SXW",
    "52": "SGW2",
    "53": "SGW3",
    "54": "SGW4",
    "55": "SGW5",
    "56": "SGW6",
    "57": "SGW7",
    "58": "SGW8",
    "59": "SGW9",
    "60": "LSW0",
    "61": "LSW1",
    "62": "LSW2",
    "63": "LSW3",
    "64": "LSW4",
    "65": "LSW5",
    "66": "LSW6",
    "67": "LSW7",
    "68": "LSW8",
    "69": "LSW9",
    "70": "SSW0",
    "71": "SSW1",
    "72": "SSW2",
    "73": "SSW3",
    "74": "SSW4",
    "75": "SSW5",
    "76": "SSW6",
    "77": "SSW7",
    "78": "SSW8",
    "79": "SSW9",
    "80": "*IOR",
    "81": "QUIT",
    "82": "GETM",
    "83": "SETM",
    "84": "TRAP",
    "85": "TRA",
    "86": "TR",
    "87": "IDLE",
    "88": "ADD",
    "89": "SUB",
    "90": "IO0",
    "91": "IO1",
    "92": "IO2",
    "93": "IO3",
    "94": "IO4",
    "95": "*ARRCMP",
    "96": "*WM",
    "97": "*BM",
    "98": "FADD",
    "99": "FSUB",
    "A": "LI0A",
    "B": "LI0B",
    "C": "LI0C",
    "D": "LI0D",
    "E": "LI0E",
    "F": "LI0F",
    "1A": "JFSC",
    "1B": "JFS",
    "1C": "JBLC",
    "1D": "JBL",
    "1E": "JBSC",
    "1F": "JBS",
    "2A": "LLW0A",
    "2B": "LLW0B",
    "2C": "LLW0C",
    "2D": "LLW0D",
    "2E": "LLW0E",
    "2F": "LLW0F",
    "3A": "SLW0A",
    "3B": "SLW0B",
    "3C": "SLW0C",
    "3D": "SLW0D",
    "3E": "SLW0E",
    "3F": "SLW0F",
    "4A": "LGW0A",
    "4B": "LGW0B",
    "4C": "LGW0C",
    "4D": "LGW0D",
    "4E": "LGW0E",
    "4F": "LGW0F",
    "5A": "SGW0A",
    "5B": "SGW0B",
    "5C": "SGW0C",
    "5D": "SGW0D",
    "5E": "SGW0E",
    "5F": "SGW0F",
    "6A": "LSW0A",
    "6B": "LSW0B",
    "6C": "LSW0C",
    "6D": "LSW0D",
    "6E": "LSW0E",
    "6F": "LSW0F",
    "7A": "SSW0A",
    "7B": "SSW0B",
    "7C": "SSW0C",
    "7D": "SSW0D",
    "7E": "SSW0E",
    "7F": "SSW0F",
    "8A": "MUL",
    "8B": "DIV",
    "8C": "SHL",
    "8D": "SHR",
    "8E": "ROL",
    "8F": "ROR",
    "9A": "FMUL",
    "9B": "FDIV",
    "9C": "FCMP",
    "9D": "FABS",
    "9E": "FNEG",
    "9F": "FFCT",
    "A0": "LSS",
    "A1": "LEQ",
    "A2": "GTR",
    "A3": "GEQ",
    "A4": "EQU",
    "A5": "NEQ",
    "A6": "ABS",
    "A7": "NEG",
    "A8": "OR",
    "A9": "AND",
    "AA": "XOR",
    "AB": "BIC",
    "AC": "IN",
    "AD": "BIT",
    "AE": "NOT",
    "AF": "MOD",
    "B0": "DECS",
    "B1": "DROP",
    "B2": "LODFV",
    "B3": "STORE",
    "B4": "STOFV",
    "B5": "COPT",
    "B6": "CPCOP",
    "B7": "PCOP",
    "B8": "*FOR1",
    "B9": "*FOR2",
    "BA": "*ENTC",
    "BB": "*XIT",
    "BC": "ADDPC",
    "BD": "JMP",
    "BE": "ORJP",
    "BF": "ANDJP",
    "C0": "MOVE",
    "C1": "CHKNIL",
    "C2": "LSTA",
    "C3": "COMP",
    "C4": "GB",
    "C5": "GB1",
    "C6": "CHK",
    "C7": "CHKZ",
    "C8": "ALLOC",
    "C9": "ENTR",
    "CA": "RTN",
    "CB": "NOP",
    "CC": "CX",
    "CD": "CI",
    "CE": "CF",
    "CF": "CL",
    "D0": "CL0",
    "D1": "CL1",
    "D2": "CL2",
    "D3": "CL3",
    "D4": "CL4",
    "D5": "CL5",
    "D6": "CL6",
    "D7": "CL7",
    "D8": "CL8",
    "D9": "CL9",
    "DA": "CL0A",
    "DB": "CL0B",
    "DC": "CL0C",
    "DD": "CL0D",
    "DE": "CL0E",
    "DF": "CL0F",
    "E0": "INCL",
    "E1": "EXCL",
    "E2": "*INL",
    "E3": "*QUOT",
    "E4": "INC1",
    "E5": "DEC1",
    "E6": "INC",
    "E7": "DEC",
    "E8": "STOT",
    "E9": "LODT",
    "EA": "LXA",
    "EB": "LPC",
    "EC": "**BBU",
    "ED": "**BBP",
    "EE": "**BBLT",
    "EF": "PDX",
    "F0": "SWAP",
    "F1": "LPA",
    "F2": "LPW",
    "F3": "SPW",
    "F4": "SSWU",
    "F5": "RCHK",
    "F6": "RCHZ",
    "F7": "CM",
    "F8": "CHKBX",
    "F9": "BMG",
    "FA": "ACTIV",
    "FB": "USR",
    "FC": "SYS",
    "FD": "NII",
    "FE": "DOT",
    "FF": "INVLD"
}
