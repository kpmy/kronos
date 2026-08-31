package inn.ocsf.kronos4j.vm;

import org.apache.commons.lang3.Conversion;
import org.apache.commons.lang3.NotImplementedException;

import java.util.Arrays;

public class VirtualMemory {
    private final int IGD480base   = 0x1F0000;    // 8MB
    private final int IGD480offset = 0x008000;    // bitmap offset
    private final int IGD480bitmap = 0x1F8000;    // bitmap base
    private final int IGD480size   = 512 * 512 / 8;

    byte[] data;
    private final int memorySizeBytes;
    private final int memorySize;
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
        pointer.getValue();
        return pointer;
    }

    int bbu(int adr, int i, int sz) {
        int byteIdx = adr + (i >> 5);

        long q = 0;
        for (int b = 0; b < 4; b++) {
            int bbyteIdx = byteIdx + b;
            if(bbyteIdx < 0 || bbyteIdx >= data.length) {
                throw new IllegalArgumentException();
            }
            q |= ((long) (data[bbyteIdx] & 0xFF)) << (b * 8);
        }

        q = q >>> (i & 0x1F);
        int d = (int) q;

        // Используем 1L << sz, чтобы избежать переполнения int при sz = 32
        int mask = (int) ((1L << sz) - 1);
        return d & mask;
    }

    void bbp(int adr, int i, int sz, int j) {
        // Вычисляем маску wmask как long, чтобы корректно поддерживать sz до 32 бит
        long wmask = (1L << sz) - 1;
        long q = j & wmask;
        long mask = wmask; // mask теперь изначально типа long

        int shift = i & 0x1F;
        q = q << shift;
        mask = mask << shift;

        int byteIdx = adr + (i >> 5);

        long currentQ = 0;
        for (int b = 0; b < 4; b++) {
            int bbyteIdx = byteIdx + b;
            if(bbyteIdx < 0 || bbyteIdx >= data.length) {
                throw new IllegalArgumentException();
            }
            currentQ |= ((long) (data[bbyteIdx] & 0xFF)) << (b * 8);
        }

        // Теперь ~mask инвертирует честные 64 бита, не затрагивая лишнего
        currentQ = (currentQ & ~mask) | q;

        for (int b = 0; b < 4; b++) {
            int bbyteIdx = byteIdx + b;
            if(bbyteIdx < 0 || bbyteIdx >= data.length) {
                throw new IllegalArgumentException();
            }
            data[bbyteIdx] = (byte) (currentQ >>> (b * 8));
        }
    }

    /*
    * addressing words (32-bit)
     */
    public static class VirtualMemoryPointer {

        private VirtualMemory memory;

        private Integer address;

        private Integer _offset;

        private Integer _byte_offset;

        private Integer _byte_count;

        private byte[] _area = new byte[4];

        private VirtualMemoryPointer(){

        }

        public int getValue(int offset) {
            if (address == null) {
                _offset = null;
                _area = new byte[4];
                return 0;
            }
            if (address + offset >= memory.memorySize) {
                memory.outOfRange = true; //TODO нужно ли это???
            }
            _offset = offset;
            System.arraycopy(memory.data, 4 * (address + offset), _area, 0, 4);
            int value = Conversion.byteArrayToInt(memory.data, 4 * (address + offset), 0, 0, 4);
            return value;
        }

        public int getValue() {
            return getValue(0);
        }

        public void setValue(int offset, int value) {
            if (address == null)
                return;
            if (address + offset == 145222) {
                address = address; //TODO debug memory cell
            }
            Conversion.intToByteArray(value, 0, memory.data, 4 * (address + offset), 4);
        }

        public void setValue(int value) {
            setValue(0, value);
        }

        public int getValueBytes(int byteOffset, int nOfBytes) {
            byte[] word = new byte[4];
            int offset = byteOffset / 4;
            int cidx = byteOffset % 4;
            int value0 = getValue(offset);
            int value1;
            Conversion.intToByteArray(value0, 0, word, 0, 4);
            if (cidx + nOfBytes > word.length) {
                value1 = getValue(offset + 1);
                byte[] longword = new byte[8];
                System.arraycopy(word, 0, longword, 0, word.length);
                Conversion.intToByteArray(value1, 0, longword, 4, 4);
                word = longword;
            }
            _byte_offset = cidx;
            _byte_count = nOfBytes;
            return Conversion.byteArrayToInt(word, cidx, 0, 0, nOfBytes);
        }

        public void setValues(byte[] data) {
            System.arraycopy(data, 0, memory.data, address * 4, data.length);
        }

        public void setValueBytes(int byteOffset, int nOfBytes, byte[] data) {
            byte[] word = new byte[4];
            int offset = byteOffset / 4;
            int cidx = byteOffset % 4;
            int oldValue0 = getValue(offset);
            if (cidx + nOfBytes > word.length) {
                throw new NotImplementedException();
            }
            Conversion.intToByteArray(oldValue0, 0, word, 0, 4);
            System.arraycopy(data, 0, word, cidx, data.length);
            int newValue0 = Conversion.byteArrayToInt(word, 0, 0, 0, nOfBytes);
            setValue(offset, newValue0);
        }
    }

    public static class U {
        private int i;
        private float f;

        public U(int i, float f) {
            this.i = i;
            this.f = f;
        }

        public int getI() {
            return i;
        }

        public void setI(int i) {
            this.i = i;
        }

        public float getF() {
            return f;
        }

        public void setF(float f) {
            this.f = f;
        }
    }

    public static class FI {
        U u;

        public FI(U u) {
            this.u = u;
        }
    }
}
