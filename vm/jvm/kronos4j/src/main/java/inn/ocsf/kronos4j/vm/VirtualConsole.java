package inn.ocsf.kronos4j.vm;

import org.apache.commons.lang3.NotImplementedException;

public class VirtualConsole {
    private final int address;
    private final int ipt;
    private boolean outIptEnabled = true;
    private boolean inpIptEnabled = false;

    public VirtualConsole(int address, int ipt) {
        this.address = address;
        this.ipt = ipt;
    }

    public int inp(int addr) {
        switch (addr & 0x0003) {
            case 2:
                return 0200 | (outIptEnabled ? 0100 : 0); //0b1000_0000 | (outIptEnabled ? 0b0100_0000 : 0);
            default:
                throw new NotImplementedException();
        }
    }

    public void out(int addr, int value) {
        switch (addr & 0x0003)
        {
            case 0: inpIptEnabled = (value & 0100) != 0;    break;
            case 1:                                         break;
            case 2: outIptEnabled = (value & 0100) != 0;    break;
            case 3: System.out.print((char)value);             break;
        }
    }

    public int getAddress() {
        return address;
    }
}
