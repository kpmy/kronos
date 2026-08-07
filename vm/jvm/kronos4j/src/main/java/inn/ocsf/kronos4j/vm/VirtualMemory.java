package inn.ocsf.kronos4j.vm;

import java.util.Arrays;

public class VirtualMemory {

    private byte[] data;
    private int memorySize;

    public VirtualMemory(int memorySize) {
        this.memorySize = memorySize;
        data = new byte[memorySize];
        Arrays.fill(data, (byte)0);
    }

    public void store(int offset, int length, byte[] block) {
        System.arraycopy(block, 0, data, offset, length);
    }

    public boolean isOutOfRange() {
        return false;
    }

    public int getSize() {
        return memorySize;
    }
}
