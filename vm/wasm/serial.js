export class VirtualSerial {
    inpIptEnabled = true;
    outIptEnabled = true;

    out(no, ioAddr, adr, i) {
        switch (ioAddr) {
            case 0xFBC:
                console.log(`sio out ${ioAddr.toString(16)} -> ${i}, 0x0E`); // 1 177570b 70b
                break;
            case 0xFC0:
                console.log(`sio out ${ioAddr.toString(16)} -> ${i}, 0x10`); // 2 177600b 100b
                break;
            case 0xFC4:
                console.log(`sio out ${ioAddr.toString(16)} -> ${i}, 0x12`); // 3 177610b 110b
                break;
            case 0xFC8:
                console.log(`sio out ${ioAddr.toString(16)} -> ${i}, 0x14`); // 4 177620b 120b
                break;
            case 0xFCC:
                console.log(`sio out ${ioAddr.toString(16)} -> ${i}, 0x16`); // 5 177630b 130b
                break;
            case 0xFD0:
                console.log(`sio out ${ioAddr.toString(16)} -> ${i}, 0x18`); // 6 177640b 140b
                break;
            case 0xFD4:
                console.log(`sio out ${ioAddr.toString(16)} -> ${i}, 0x1A`); // 7 177650b 150b
                break;
            case 0xFD8:
                console.log(`sio out ${ioAddr.toString(16)} -> ${i}, 0x1C`); // 8 177660b 160b
                break;
            case 0xFDC:
                console.log(`sio out ${ioAddr.toString(16)} -> ${i}, 0x1E`); // 0 177670b 170b mouse(0xFDC, 0x1E);
                this.mouse(0xFDC, 0x1E);
                break;
            default:
                console.error(`NotImplementedException: out ${no.toString(16)} ${ioAddr.toString(16)}`);
        }
    }

    inp(no, ioAddr, addr) {
        let ret;

        switch (addr & 0x0003) {
            case 0:
                ret = this.inpIptEnabled ? 0o100 : 0;
                break;
            case 2:
                ret = 0o200 | (this.outIptEnabled ? 0o100 : 0);
                break;
            default:
                console.error("NotImplementedException", addr & 0x0003);
        }

        switch (ioAddr) {
            case 0xFBC:
                console.log(`sio in ${ioAddr.toString(16)}, 0x0E`); // 1 177570b 70b
                break;
            case 0xFC0:
                console.log(`sio in ${ioAddr.toString(16)}, 0x10`); // 2 177600b 100b
                break;
            case 0xFC4:
                console.log(`sio in ${ioAddr.toString(16)}, 0x12`); // 3 177610b 110b
                break;
            case 0xFC8:
                console.log(`sio in ${ioAddr.toString(16)}, 0x14`); // 4 177620b 120b
                break;
            case 0xFCC:
                console.log(`sio in ${ioAddr.toString(16)}, 0x16`); // 5 177630b 130b
                break;
            case 0xFD0:
                console.log(`sio in ${ioAddr.toString(16)}, 0x18`); // 6 177640b 140b
                break;
            case 0xFD4:
                console.log(`sio in ${ioAddr.toString(16)}, 0x1A`); // 7 177650b 150b
                break;
            case 0xFD8:
                console.log(`sio in ${ioAddr.toString(16)}, 0x1C`); // 8 177660b 160b
                break;
            case 0xFDC:
                console.log(`sio in ${ioAddr.toString(16)}, 0x1E`); // 0 177670b 170b mouse(0xFDC, 0x1E);
                this.mouse(0xFDC, 0x1E);
                break;
            default:
                console.error(`NotImplementedException: in ${no.toString(16)} ${ioAddr.toString(16)}`);
        }

        return ret;
    }

    mouse(ioAddr, val) {
        // Заглушка для метода mouse
    }
}
