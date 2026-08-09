package inn.ocsf.kronos4j.vm;

import org.apache.commons.io.EndianUtils;
import org.apache.commons.lang3.Conversion;

import java.util.Arrays;

public class VirtualMemory {
    private final int IGD480base   = 0x1F0000;    // 8MB
    private final int IGD480offset = 0x008000;    // bitmap offset
    private final int IGD480bitmap = 0x1F8000;    // bitmap base
    private final int IGD480size   = 512 * 512 / 8;

    private byte[] data;
    private int memorySizeBytes;
    private int memorySize;
    private boolean outOfRange;

    public VirtualMemory(int memorySizeBytes) {
        this.memorySizeBytes = memorySizeBytes;
        this.memorySize = (memorySizeBytes + 3) / 4;
        data = new byte[memorySizeBytes];
        Arrays.fill(data, (byte)0);
        outOfRange = false;
    }

    public void store(int offset, int length, byte[] block) {
        System.arraycopy(block, 0, data, offset, length);
    }

    public boolean isOutOfRange() {
        boolean wasOutOfRange = outOfRange;
        outOfRange = false;
        return wasOutOfRange;
    }

    public int getSize() {
        return memorySize;
    }

    VirtualMemoryPointer getPointer(int n) {
        VirtualMemoryPointer pointer = new VirtualMemoryPointer();
        pointer.memory = this;
        n &= ~0xC0000000; // clear bits {31,30} Kronos feature
        if (n >= 0 && n < memorySize) {
            pointer.address = n;
        } else if (n >= IGD480base && n <= IGD480base + IGD480offset + IGD480size) {
            pointer.address = n;
        } else {
            pointer.address = null;
            outOfRange = true;
        }
        return pointer;
    }

    /*
    * addressing words (32-bit)
     */
    public static class VirtualMemoryPointer {

        private VirtualMemory memory;

        private Integer address;

        private byte[] area = new byte[4];

        private VirtualMemoryPointer(){

        }

        public int getValue(int idx) {
            if (address == null)
                return 0;
            if (address + idx >= memory.memorySize) {
                memory.outOfRange = true; //TODO нужно ли это???
            }
            System.arraycopy(memory.data, 4 * (address + idx), area, 0, 4);
            int value = Conversion.byteArrayToInt(memory.data, 4 * (address + idx), 0, 0, 4);
            return value;
        }

        public int getValue() {
            return getValue(0);
        }

        public void setValue(int value) {
            if (address == null)
                return;
            Conversion.intToByteArray(value, 0, memory.data, 4 * address, 4);
        }
    }
}
