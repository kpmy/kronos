package inn.ocsf.kronos4j.vm;

import org.apache.commons.lang3.NotImplementedException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class VirtualSerial {

    private final Logger log =  LoggerFactory.getLogger(VirtualSerial.class);

    boolean inpIptEnabled = true;
    boolean outIptEnabled = true;

    public VirtualSerial() {

    }

    public void out(int no, int ioAddr, int adr, int i) {
        switch (ioAddr) {
            case 0xFBC -> log.info("sio out {} -> {}, 0x0E", String.format("%x", ioAddr), i);   // 1 177570b  70b
            case 0xFC0 -> log.info("sio out {} -> {}, 0x10", String.format("%x", ioAddr), i);   // 2 177600b 100b
            case 0xFC4 -> log.info("sio out {} -> {}, 0x12", String.format("%x", ioAddr), i);   // 3 177610b 110b
            case 0xFC8 -> log.info("sio out {} -> {}, 0x14", String.format("%x", ioAddr), i);   // 4 177620b 120b
            case 0xFCC -> log.info("sio out {} -> {}, 0x16", String.format("%x", ioAddr), i);   // 5 177630b 130b
            case 0xFD0 -> log.info("sio out {} -> {}, 0x18", String.format("%x", ioAddr), i);   // 6 177640b 140b
            case 0xFD4 -> log.info("sio out {} -> {}, 0x1A", String.format("%x", ioAddr), i);   // 7 177650b 150b
            case 0xFD8 -> log.info("sio out {} -> {}, 0x1C", String.format("%x", ioAddr), i);   // 8 177660b 160b
            case 0xFDC -> log.info("sio out {} -> {}, 0x1E", String.format("%x", ioAddr), i);   // 0 177670b 170b mouse(0xFDC, 0x1E);
            default -> {
                throw new NotImplementedException(String.format("out %x %x", no, ioAddr));
            }
        }
    }

    public Integer inp(int no, int ioAddr, int addr) {
        Integer ret;
        switch (addr & 0x0003) {
            case 0 -> ret = (inpIptEnabled ? 0100 : 0);
            case 2 -> ret = 0200 | (outIptEnabled ? 0100 : 0); //0b1000_0000 | (outIptEnabled ? 0b0100_0000 : 0);
            default -> throw new NotImplementedException();
        }
        switch (ioAddr) {
            case 0xFBC -> log.info("sio in {}, 0x0E", String.format("%x", ioAddr));   // 1 177570b  70b
            case 0xFC0 -> log.info("sio in {}, 0x10", String.format("%x", ioAddr));   // 2 177600b 100b
            case 0xFC4 -> log.info("sio in {}, 0x12", String.format("%x", ioAddr));   // 3 177610b 110b
            case 0xFC8 -> log.info("sio in {}, 0x14", String.format("%x", ioAddr));   // 4 177620b 120b
            case 0xFCC -> log.info("sio in {}, 0x16", String.format("%x", ioAddr));   // 5 177630b 130b
            case 0xFD0 -> log.info("sio in {}, 0x18", String.format("%x", ioAddr));   // 6 177640b 140b
            case 0xFD4 -> log.info("sio in {}, 0x1A", String.format("%x", ioAddr));   // 7 177650b 150b
            case 0xFD8 -> log.info("sio in {}, 0x1C", String.format("%x", ioAddr));   // 8 177660b 160b
            case 0xFDC -> log.info("sio in {}, 0x1E", String.format("%x", ioAddr));   // 0 177670b 170b mouse(0xFDC, 0x1E);
            default -> {
                throw new NotImplementedException(String.format("in %x %x", no, ioAddr));
            }
        }
        return ret;
    }
}
