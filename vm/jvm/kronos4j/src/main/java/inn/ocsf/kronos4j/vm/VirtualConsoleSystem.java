package inn.ocsf.kronos4j.vm;

import org.apache.commons.lang3.NotImplementedException;

public class VirtualConsoleSystem implements VirtualConsole {
    private static final int EMPTY_CHAR = 512;

    private final int address;
    private final int ipt;
    private boolean outIptEnabled = true;
    private boolean inpIptEnabled = true;
    private int inChar;

    public VirtualConsoleSystem(int address, int ipt) {
        this.address = address;
        this.ipt = ipt;
        inChar = EMPTY_CHAR;
    }

    @Override
    public int inp(int addr) {
        switch (addr & 0x0003) {
            case 0:
                if (inChar == EMPTY_CHAR) {
                    //inChar = po->busyRead();
                }
                return (inpIptEnabled ? 0100 : 0) | (inChar != EMPTY_CHAR ? 0200 : 0);
            case 2:
                return 0200 | (outIptEnabled ? 0100 : 0); //0b1000_0000 | (outIptEnabled ? 0b0100_0000 : 0);
            default:
                throw new NotImplementedException();
        }
    }

    @Override
    public void out(int addr, int value) {
        switch (addr & 0x0003)
        {
            case 0: inpIptEnabled = (value & 0100) != 0;    break;
            case 1:                                         break;
            case 2: outIptEnabled = (value & 0100) != 0;    break;
            case 3: System.out.print((char)value);             break;
        }
    }

    @Override
    public int getAddress() {
        return address;
    }

    @Override
    public int getIpt() {
        return ipt;
    }

    @Override
    public boolean isOutIptEnabled() {
        return outIptEnabled;
    }

    @Override
    public boolean isInpIptEnabled() {
        return inpIptEnabled;
    }
}
