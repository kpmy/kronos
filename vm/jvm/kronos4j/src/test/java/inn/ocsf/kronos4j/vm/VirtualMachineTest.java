package inn.ocsf.kronos4j.vm;

import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

public class VirtualMachineTest {

    VirtualMachine vm;

    @BeforeEach
    public void setup() {
        vm = new VirtualMachine(1024);
        byte[] boot = new byte[]{
                0x0, 0x0, 0x0, 0x0, //empty
                0x8, 0x0, 0x0, 0x0, //p
                0x0, 0x0, 0x0, 0x0,
                0x0, 0x0, 0x0, 0x0,
                0x0, 0x0, 0x0, 0x0,
                0x0, 0x0, 0x0, 0x0,
                0x0, 0x0, 0x0, 0x0,
                0x0, 0x0, 0x0, 0x0,
                0x10, 0x0, 0x0, 0x0, //g
                0x0, 0x0, 0x0, 0x0, //l
                0x0, 0x0, 0x0, 0x0, //pc
                0x0, 0x0, 0x0, 0x0, //m
                0x0, 0x2, 0x0, 0x0, //h
                0x10, 0x2, 0x0, 0x0, //s
                0x0, 0x0, 0x0, 0x0,
                0x0, 0x0, 0x0, 0x0,
                0x20, 0x0, 0x0, 0x0, //f
                0x0, 0x0, 0x0, 0x0,
                0x0, 0x0, 0x0, 0x0,
                0x0, 0x0, 0x0, 0x0,
                0x0, 0x0, 0x0, 0x0,
                0x0, 0x0, 0x0, 0x0,
                0x0, 0x0, 0x0, 0x0,
                0x0, 0x0, 0x0, 0x0,
                0x0, 0x0, 0x0, 0x0,
                0x0, 0x0, 0x0, 0x0,
                0x0, 0x0, 0x0, 0x0,
                0x0, 0x0, 0x0, 0x0,
                0x0, 0x0, 0x0, 0x0,
                0x0, 0x0, 0x0, 0x0,
                0x0, 0x0, 0x0, 0x0,
                0x0, 0x0, 0x0, 0x0,
                0x0, 0x0, 0x0, 0x0,

        };
        vm.getMemory().store(0, boot.length, boot);
        vm.start();
    }

    @Test
    public void testInstructionsAll() throws InterruptedException {
        for(int ir = 0x0; ir < 0xFF; ir++){
            vm.patch(ir);
            boolean badIrq = false;
            try {
                badIrq = vm.step();
                assertFalse(badIrq);
                switch (ir) {
                    case 0x0:
                    case 0x1:
                    case 0x2:
                    case 0x3:
                    case 0x4:
                    case 0x5:
                    case 0x6:
                    case 0x7:
                    case 0x8:
                    case 0x9:
                    case 0xA:
                    case 0xB:
                    case 0xC:
                    case 0xD:
                    case 0xE:
                    case 0xF:
                        int top = vm.getAtStack();
                        assertTrue(top >= 0 && top < 0xF, "immediate load");
                        break;

                    default:
                        //throw new RuntimeException("unknown ir %x".formatted(ir));
                        break;
                }
            } catch (Exception e) {
                switch (ir) {
                    case 0xEC: // BBU  Bit Block Unpack
                    case 0xED: // BBP  Bit Block Pack
                    case 0xEE: // BBLT Bit BLock Transfer
                        //really unimplemented, skip for now
                        break;
                    default:
                        throw new RuntimeException(e);
                }
            }
        }
    }
}
