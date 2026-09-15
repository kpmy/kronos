export const EMPTY_CHAR = 512;

export class VirtualConsole {

    address
    ipt
    inpIptEnabled
    outIptEnabled
    inChar

    inputQueue = [];

    constructor(address, ipt) {
        this.address = address;
        this.ipt = ipt;

        this.inpIptEnabled = false
        this.outIptEnabled = false
        this.inChar = EMPTY_CHAR
    }

    read(input) {
        this.inputQueue.push(input);
    }

    write(output) {

    }

    // Хак-конвертер для подбора кодировки Кроноса
    _writeGuestChar(value) {
        // 1. Если это стандартный ASCII (0-127), выводим как есть (латиница, цифры, системные символы)
        if (value <= 127) {
            this.write(String.fromCharCode(value));
            return;
        }

        // 2. Набор наиболее вероятных однобайтовых кириллических кодировок для Kronos/Excelsior:
        // Попробуйте менять индекс ('koi8-r', 'ibm866', 'windows-1251', 'iso-8859-5')
        const targetEncoding = 'koi8-r'; // <-- Поменяйте здесь, если текст останется "кракозябрами"

        try {
            const uint8Array = new Uint8Array([value]);
            const decoder = new TextDecoder(targetEncoding);
            const decodedChar = decoder.decode(uint8Array);

            this.write(decodedChar);
        } catch (e) {
            // Фолбэк, если TextDecoder не сдюжил
            this.write(Buffer.from([value]));
        }
    }

    getAddress() {
        return this.address;
    }

    getIpt() {
        return this.ipt;
    }

    inp(addr) {
        switch (addr & 0x0003) {
            case 0:
                if (this.inChar === EMPTY_CHAR) {
                    this.inChar = this.busyRead();
                }
                return (this.inpIptEnabled ? 0o100 : 0) | (this.inChar !== EMPTY_CHAR ? 0o200 : 0);
            case 1:
                {
                    if (this.inChar === EMPTY_CHAR) {
                        this.inChar = this.busyRead();
                    }
                    let data = this.inChar === EMPTY_CHAR ? 0 : this.inChar;
                    this.inChar = EMPTY_CHAR;
                    return data & 0xFF;
                }
            case 2:
                return 0o200 | (this.outIptEnabled ? 0o100 : 0); //0b1000_0000 | (outIptEnabled ? 0b0100_0000 : 0);
            case 3:
                return 0;
            default:
                throw "addr not implemented";
        }
    }

    out(addr, value) {
        switch (addr & 0x0003)
            {
                case 0: this.inpIptEnabled = (value & 0o100) !== 0;    break;
                case 1:                                         break;
                case 2: this.outIptEnabled = (value & 0o100) !== 0;    break;
                case 3: this._writeGuestChar(value); break;//process.stdout.write(Buffer.from([value]));             break;
            }
    }

    isOutIptEnabled() {
        return this.outIptEnabled;
    }

    isInpIptEnabled() {
        if (this.inChar === EMPTY_CHAR) {
            this.inChar = this.busyRead();
        }
        return this.inpIptEnabled && this.inChar !== EMPTY_CHAR;
    }

    busyRead() {
        let res = EMPTY_CHAR;
        if (this.inputQueue.length > 0) {
            res = this.inputQueue.shift();
        }
        return res
    }
}
