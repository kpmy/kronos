package inn.ocsf.kronos4j.vm;

import java.util.Arrays;

public class VirtualMemory {
    private final int IGD480base   = 0x1F0000;    // 8MB
    private final int IGD480offset = 0x008000;    // bitmap offset
    private final int IGD480bitmap = 0x1F8000;    // bitmap base
    private final int IGD480size   = 512 * 512 / 8;

    private byte[] data;
    private int memorySize;
    private boolean outOfRange;

    public VirtualMemory(int memorySize) {
        this.memorySize = memorySize;
        data = new byte[memorySize];
        Arrays.fill(data, (byte)0);
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

    public static class VirtualMemoryPointer {

        private VirtualMemory memory;

        private Integer address;

        private VirtualMemoryPointer(){

        }

        public int getValue(int idx) {
            if (address == null)
                return 0;
            if (address + idx >= memory.memorySize) {
                memory.outOfRange = true; //TODO нужно ли это???
            }

            return memory.data[address + idx];
        }

        public int getValue() {
            if (address == null)
                return 0;
            return memory.data[address];
        }

        public void setValue(int value) {
            if (address == null)
                return;
            memory.data[address] = (byte) value;
        }
    }
}
