package inn.ocsf.kronos4j.vm;

import org.apache.commons.collections4.map.ListOrderedMap;
import org.apache.commons.collections4.queue.CircularFifoQueue;
import org.apache.commons.csv.CSVFormat;
import org.apache.commons.csv.CSVRecord;
import org.apache.commons.lang3.Conversion;
import org.apache.commons.lang3.NotImplementedException;
import org.apache.commons.lang3.tuple.Pair;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.time.LocalDateTime;
import java.util.*;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.stream.Collectors;

public class VirtualMachine {

    public static final String M_CODE_TABLE = """
            --   00     20      40      60      80     A0     C0     E0
            
            00   LI0    LLW     LXB     LSW0 *IOR     LSS    MOVE   INCL
            01   LI1    LGW     LXW     LSW1    QUIT   LEQ  **CHKNIL EXCL
            02   LI2    LEW     LGW2    LSW2    GETM   GTR    LSTA  *INL
            03   LI3    LSW     LGW3    LSW3    SETM   GEQ    COMP  *QUOT
            04   LI4    LLW4    LGW4    LSW4    TRAP   EQU    GB     INC1
            05   LI5    LLW5    LGW5    LSW5    TRA    NEQ    GB1    DEC1
            06   LI6    LLW6    LGW6    LSW6    TR     ABS    CHK    INC
            07   LI7    LLW7    LGW7    LSW7    IDLE   NEG    CHKZ   DEC
            
            08   LI8    LLW8    LGW8    LSW8    ADD    OR     ALLOC  STOT
            09   LI9    LLW9    LGW9    LSW9    SUB    AND    ENTR   LODT
            0A   LI0A   LLW0A   LGW0A   LSW0A   MUL    XOR    RTN    LXA
            0B   LI0B   LLW0B   LGW0B   LSW0B   DIV    BIC    NOP    LPC
            0C   LI0C   LLW0C   LGW0C   LSW0C   SHL    IN     CX   **BBU
            0D   LI0D   LLW0D   LGW0D   LSW0D   SHR    BIT    CI   **BBP
            0E   LI0E   LLW0E   LGW0E   LSW0E   ROL    NOT    CF   **BBLT
            0F   LI0F   LLW0F   LGW0F   LSW0F   ROR    MOD    CL   **PDX
            
            10   LIB    SLW     SXB     SSW0    IO0    DECS   CL0    SWAP
            11   LID    SGW     SXW     SSW1    IO1    DROP   CL1    LPA
            12   LIW    SEW     SGW2    SSW2    IO2    LODFV  CL2    LPW
            13   LIN    SSW     SGW3    SSW3    IO3    STORE  CL3    SPW
            14   LLA    SLW4    SGW4    SSW4    IO4    STOFV  CL4    SSWU
            15   LGA    SLW5    SGW5    SSW5   *ARRCMP COPT   CL5  **RCHK
            16   LSA    SLW6    SGW6    SSW6   *WM     CPCOP  CL6  **RCHZ
            17   LEA    SLW7    SGW7    SSW7   *BM     PCOP   CL7  **CM
            
            18   JFLC   SLW8    SGW8    SSW8    FADD   *FOR1  CL8   *CHKBX
            19   JFL    SLW9    SGW9    SSW9    FSUB   *FOR2  CL9   *BMG
            1A   JFSC   SLW0A   SGW0A   SSW0A   FMUL   *ENTC  CL0A   ACTIV
            1B   JFS    SLW0B   SGW0B   SSW0B   FDIV   *XIT   CL0B   USR
            1C   JBLC   SLW0C   SGW0C   SSW0C   FCMP   ADDPC  CL0C   SYS
            1D   JBL    SLW0D   SGW0D   SSW0D   FABS   JMP    CL0D **NII
            1E   JBSC   SLW0E   SGW0E   SSW0E   FNEG   ORJP   CL0E   DOT
            1F   JBS    SLW0F   SGW0F   SSW0F   FFCT   ANDJP  CL0F   INVLD
            
            """;
    public static Map<Integer, String> MCODES = new HashMap<>();
    static {
        String table = M_CODE_TABLE.replace("\r\n", "\n");
        while (table.contains("\n ")){
            table = table.replace("\n ", "\n");
        }
        while (table.contains("  ")) {
            table = table.replace("  ", " ");
        }
        table = table.replace(" ", "\t"); //now its TSV
        try {
            var records = CSVFormat.TDF.builder()
                    .setHeader()
                    .setSkipHeaderRecord(true)
                    .build()
                    .parse(new StringReader(table));
            List<String> headers = records.getHeaderNames();
            for (CSVRecord record : records) {
                String ls = "0";
                int li = 0;
                for (int l = 0; l < record.size(); l++) {
                    if(l > 0) {
                        String hs = headers.get(l);
                        int hi = Integer.parseInt(hs, 16);
                        MCODES.put(hi + li, record.get(l));
                    } else {
                        ls = record.get(l);
                        li = Integer.parseInt(ls, 16);
                    }
                }
            }
        } catch (IOException e) {
            throw new RuntimeException(e);
        };
    }

    public static final int AStackSize = 15;
    public static final int Nil = 0x7FFFFF80;
    public static final int ExternalBit = 31;

    private Logger log = LoggerFactory.getLogger(VirtualMachine.class);

    private VirtualMemory memory;

    private List<VirtualDisk> disks = new ArrayList<>();

    private VirtualConsole console;
    private VirtualSerial serial;

    private ScheduledExecutorService scheduler;

    private int
            ipt, //код прерывания
            sp, //указатель на стек выражений (верхний элемент)
            pc, //указатель на инструкцию
            pcs, //указатель на предыдущую инструкцию
            ir, //инструкция
            p, //память процесса
            l, //область локальных данных текущей процедуры на стеке
            g, //область глобальных данных модуля
            m, //маска прерываний
            h, //конец процедурного стека
            s, //указатель на процедурный стек (верхний элемент)
            f; //указатель на начало сегмента кода текущей процедуры
    private boolean bDebug = false;
    private boolean bTimer = false;
    private boolean sPause = false;


    private Queue<VirtualMachineStepDump> steps = new CircularFifoQueue<>(1024);
    private VirtualMachineStepDump currentStep = null;
    private long stepIdx = 0;
    private VirtualMachineTrace trace;

    private VirtualMemory.VirtualMemoryPointer pcode;

    private Integer[] astack = new Integer[AStackSize];

    //debug
    private final Map<Integer, Integer> irCountMap = new HashMap<>();

    public VirtualMachine(int memorySize) {
        memory = new VirtualMemory(memorySize);
        pcode = pmem(0);
        console = new VirtualConsole(0xFB8, 0x0C);
        serial = new VirtualSerial();
    }

    private void startTimer() {
        scheduler = Executors.newSingleThreadScheduledExecutor();
        scheduler.scheduleAtFixedRate(() -> {
            //bTimer = true;
        }, 0, 100, TimeUnit.MILLISECONDS);
    }

    private void stopTimer() {
        scheduler.shutdown();
    }


    private VirtualMemory.VirtualMemoryPointer pmem(int addr) {
        return memory.getPointer(addr);
    }

    public void addDisk(VirtualDisk disk) {
        disks.add(disk);
    }

    public int getDiskCount() {
        return disks.size();
    }

    public VirtualDisk getDisk(int index) {
        return disks.get(index);
    }

    public VirtualMemory getMemory() {
        return memory;
    }

    public VirtualMachineTrace getTrace() {
        return trace;
    }

    public void setTrace(VirtualMachineTrace trace) {
        this.trace = trace;
    }

    private boolean irq() {
        int d = 0;

        if (ipt == 0) {
            if (memory.isOutOfRange())
                ipt = 3;
            else if (bTimer)
            {
                if ((m & 0x2) != 0)
                {
                    bTimer = false;
                    ipt = 1; // timer ipt
                }
            }
            else if ((m & 0x1) != 0)
            {
                //SIO *s = sios.inpReady();

                // if (s != NULL)
                //     Ipt = s->ipt();
                // else
                // {
                //     s = sios.outReady();
                //     if (s != NULL)
                //         Ipt = s->ipt() + 1;
                // }
                if (console.isInpIptEnabled()) {
                    //ipt = console.getIpt();
                } else if (console.isOutIptEnabled()) {
                    ipt = console.getIpt() + 1;
                }
            }
        }
        if (ipt != 0) {
            trap(ipt);
            ipt = 0;
        }
        if (bDebug) {
            if (!debugMonitor(d))
                return false;
        }
        return true;
    }

    public void run() throws InterruptedException {
        startTimer();
        start();
        boolean badIrq = false;
        while (!sPause && !badIrq) {
            dumpStart();
            badIrq = step();
            clearStack();
            dumpStop();
            stepIdx++;
        }
        stop();
        stopTimer();
    }

    private void dumpStart() {
        currentStep = new VirtualMachineStepDump(this);
    }

    private void dumpStop() {
        currentStep.dump(this);
        steps.add(currentStep);
    }

    public boolean step() throws InterruptedException {
        if (!irq())
            return true;
        pcs = pc;
        ir = code(pc++);

        {
            int irCount = irCountMap.getOrDefault(ir, 0);
            if(irCount == 0) {
                //log.info("new IR 0x{} {}", String.format("%02X",  ir), MCODES.get(ir));
            }
            irCountMap.put(ir, irCount+1);
        }

        switch (ir) {
            case 0x0: case 0x1: case 0x2: case 0x3:
            case 0x4: case 0x5: case 0x6: case 0x7:
            case 0x8: case 0x9: case 0xA: case 0xB:
            case 0xC: case 0xD: case 0xE: case 0xF:
                push(ir & 0xF); break;
            case 0x10:  push(next());   break;
            case 0x11:  push(next2());  break;
            case 0x12:  push(next4());  break;
            case 0x13:  push(Nil);      break;
            case 0x14:  push(l+next()); break;
            case 0x15:  push(g+next()); break;
            case 0x16:  astack[sp-1] += next(); break;
            case 0x17:  push(mem(mem(g - next() - 1)) + next());    break;
            case 0x18:  if (pop() == 0) {
                int pc1 = next2();
                pc += pc1;
            } else            pc += 2;
                break;
            case 0x19: {
                int pc1 = next2();
                pc += pc1;  break;}
            case 0x1A:  if (pop() == 0) {
                int pc1 = next();
                pc += pc1;
            } else            pc++;
                break;
            case 0x1B: {
                int pc1 = next();
                pc += pc1;   break; }
            case 0x1C:  if (pop() == 0) {
                int pc1 = next2();
                pc -= pc1;
            } else            pc += 2;
                break;
            case 0x1D: {
                int pc1 = next2();
                pc -= pc1;  break; }
            case 0x1E:  if (pop() == 0) {
                int pc1 = next();
                pc -= pc1;
            } else            pc++;
                break;
            case 0x1F: {
                int pc1 = next();
                pc -= pc1;   break; }

            case 0x20:  push(mem(l + next()));  break;
            case 0x21:  push(mem(g + next()));  break;
            case 0x22:  push(mem(mem(mem(g - next() - 1)) + next())); break;

            case 0x23:  push(mem(pop() + next()));  break;

            case 0x24:  case 0x25:  case 0x26:  case 0x27:
            case 0x28:  case 0x29:  case 0x2A:  case 0x2B:
            case 0x2C:  case 0x2D:  case 0x2E:  case 0x2F:
                push(mem(l + (ir & 0xF)));
                break;

            case 0x30:  mem(l + next(), pop()); break;
            case 0x31:  mem(g + next(),  pop()); break;
            case 0x32:  mem(mem(mem(g - next() - 1)) + next(),  pop()); break;
            case 0x33:  { int i = pop(); mem(pop() + next(), i); break; }

            case 0x34:  case 0x35:  case 0x36:  case 0x37:
            case 0x38:  case 0x39:  case 0x3A:  case 0x3B:
            case 0x3C:  case 0x3D:  case 0x3E:  case 0x3F:
                mem(l + (ir & 0xF),  pop());
                break;

            case 0x40:  {   int i = pop();
                int j = pop();
                VirtualMemory.VirtualMemoryPointer s = pmem(j + i / 4);
                push(s.getValueBytes(i % 4, 1));
                break;
            }

            case 0x41:  push(mem(pop() + pop()));   break;

            case 0x42:  case 0x43:
            case 0x44:  case 0x45:  case 0x46:  case 0x47:
            case 0x48:  case 0x49:  case 0x4A:  case 0x4B:
            case 0x4C:  case 0x4D:  case 0x4E:  case 0x4F:
                push(mem(g + (ir & 0xF)));
                break;

            case 0x50:
            {
                int k = pop();
                int i = pop();
                int j = pop();
                int s = mem(j + i / 4);
                //((byte*)&s)[i % 4] = (byte)k; //rewrite
                int pos = i % 4;                 // byte index: 0 = LSB, 3 = MSB
                //int mask = 0xFF << (pos * 8);    // mask for the target byte
                //s = (s & ~mask) | ((k & 0xFF) << (pos * 8));
                byte[] sa = new byte[4];
                Conversion.intToByteArray(s, 0, sa, 0, 4);
                sa[pos] = (byte) k;
                s = Conversion.byteArrayToInt(sa, 0, 0, 0, 4);
                mem(j + i / 4, s);
                break;
            }

            case 0x51:  { int i = pop(); mem(pop() + pop(),  i); break; }
            case 0x52:  case 0x53:
            case 0x54:  case 0x55:  case 0x56:  case 0x57:
            case 0x58:  case 0x59:  case 0x5A:  case 0x5B:
            case 0x5C:  case 0x5D:  case 0x5E:  case 0x5F:
                mem(g + (ir & 0xF),  pop());
                break;

            case 0x60:  case 0x61:  case 0x62:  case 0x63:
            case 0x64:  case 0x65:  case 0x66:  case 0x67:
            case 0x68:  case 0x69:  case 0x6A:  case 0x6B:
            case 0x6C:  case 0x6D:  case 0x6E:  case 0x6F:
                astack[sp-1] = mem(astack[sp-1] + (ir & 0xF));
                break;

            case 0x70:  case 0x71:  case 0x72:  case 0x73:
            case 0x74:  case 0x75:  case 0x76:  case 0x77:
            case 0x78:  case 0x79:  case 0x7A:  case 0x7B:
            case 0x7C:  case 0x7D:  case 0x7E:  case 0x7F:
            {
                int i = pop(); mem(pop() + (ir & 0xF), i);
                break;
            }

            case 0x80: // I/O bus reset
                break;
            case 0x81: // QUIT Stop processor
                bDebug = true; //do nothing
                break;
            case 0x82: // GETM Get Mask
                push(m);
                break;
            case 0x83: // SETM Set Mask
                m = pop();
                break;
            case 0x84: // TRAP interrupt simulation
                ipt = pop();
                //ipt = astack[sp-1];
                break;
            case 0x85: // TRA  Transfer control between processes
            {
                int i = pop(); transfer(i, pop());
                break;
            }
            case 0x86: // TR    Test & Reset
            {
                int i = pop(); push(mem(i)); mem(i, 0);
                break;
            }

            case 0x87:  // IDLE
            {
                pc--;
                Thread.sleep(1);
                // no enabled interrupts => infinite idle
                // dsu -p uses this to shutdown computer.
                if (m == 0)
                {
                    //igd.shutdown(); //TODO igd
                    return true;
                }
                break;
            }
            case 0x88: // ADD
                if (sp <= 1) ipt = 0x4C;
                else { sp--; astack[sp-1] += astack[sp]; }
                break;

            case 0x89: // sub
                if (sp <= 1) ipt = 0x4C;
                else { sp--; astack[sp-1] -= astack[sp]; }
                break;

            case 0x8A: // mul
                if (sp <= 1) ipt = 0x4C;
                else { sp--; astack[sp-1] *= astack[sp]; }
                break;

            case 0x8B: // div
                if (sp <= 1)
                    ipt = 0x4C;
                else if (astack[sp-1] == 0)
                {
                    ipt = 0x41; sp--; astack[sp-1] = 0;
                }
                else
                {
                    sp--; astack[sp-1] = idiv(astack[sp-1], astack[sp]);
                }
                break;

            case 0x8C: // SHL  integer SHift Left
            {
                int i = pop() & 0x1F; push(pop() << i); break;
            }

            case 0x8D: // SHR  integer SHift Right
            {
                int i = pop() & 0x1F; push(pop() >> i); break;
            }

            case 0x8E: // ROL  word ROtate Left
            {   int i = pop() & 0x1F;
                if (i != 0)
                {
                    int j = pop();
                    push(Integer.rotateLeft(j, i));
                }
                break;
            }
            case 0x8F: // ROR  word ROtate Right
            {
                int i = pop() & 0x1F;
                if (i != 0)
                {
                    int j = pop();
                    push(Integer.rotateRight(j, i));
                }
                break;
            }

            case 0x90:  case 0x91:  case 0x92:  case 0x93: case 0x94:   // io0..4
                io(ir & 0xF);
                break;

            case 0x95: // rcmp A.K.A. ARRCMP array compare
            {
                int sz = pop();
                int adr = pop();
                int adr1 = pop();
                if (sz < 0)
                {
                    push(sz); ipt = 0x4F;
                }
                else if (sz == 0)
                {
                    push(adr1);
                    push(adr1);
                }
                else
                {
                    for (;;)
                    {
                        if (mem(adr) != mem(adr1) || sz ==1)
                        {
                            push(adr1); push(adr); break;
                        }
                        sz--;
                        adr++;
                        adr1++;
                    }
                }
                break;
            }

            case 0x96: // wmv A.K.A. WM     word move
            {
                int sz = pop();
                int f  = pop();
                int t  = pop();
                if (t > f)
                {
                    t = t + sz - 1;
                    f = f + sz - 1;
                    while (sz > 0)
                    {
                        mem(t, mem(f));
                        t--; f--; sz--;
                    }
                }
                else if (sz > 0)
                {
                    byte[] mf = mmem(f, sz*4);
                    mmem(t, sz*4, mf);
                }
                break;
            }

            case 0x97:  // BMV
            {
                int sz = pop();
                int i = pop(); int j = pop();
                int a = pop(); int b = pop();
                bitmove(b, a, j, i, sz);
                break;
            }

            case 0x98:  case 0x99:  case 0x9A:  case 0x9B:
            case 0x9C:  case 0x9D:  case 0x9E:  case 0x9F:
                fpu();
                break;
            case 0xA0: // LSS  int LeSS
                if (sp <= 1) ipt = 0x4C;
                else { sp--; astack[sp-1] = astack[sp-1] < astack[sp] ? 1 : 0; }
                break;

            case 0xA1:  // LEQ  int Less or EQual
                if (sp <= 1)
                    ipt = 0x4C;
                else
                {
                    sp--;
                    astack[sp-1] = astack[sp-1] <= astack[sp] ? 1 : 0;
                }
                break;

            case 0xA2: // GTR  int Greater or EQual
                if (sp <= 1)
                    ipt = 0x4C;
                else
                {
                    sp--;
                    astack[sp-1] = astack[sp-1] > astack[sp] ?  1 : 0;
                }
                break;

            case 0xA3:  // GEQ  int Greater or EQual
                if (sp <= 1)
                    ipt = 0x4C;
                else
                {
                    sp--;
                    astack[sp-1] = astack[sp-1] >= astack[sp] ? 1 : 0;
                }
                break;

            case 0xA4: // EQU  int EQUal
                if (sp <= 1)
                    ipt = 0x4C;
                else
                {
                    sp--;
                    astack[sp-1] = (int) astack[sp-1] == astack[sp] ? 1 : 0;
                }
                break;

            case 0xA5:  // NEQ  int Not EQual
                if (sp <= 1)
                    ipt = 0x4C;
                else
                {
                    sp--; astack[sp-1] = (int) astack[sp-1] != astack[sp] ? 1 : 0;
                }
                break;

            case 0xA6:  // ABS  int ABSolute value
            {
                int i = pop();
                push(i < 0 ? -i : i);
                break;
            }
            case 0xA7:  push(-pop()); break;
            case 0xA8:  push(pop() | pop()); break;
            case 0xA9:  push(pop() & pop()); break;
            case 0xAA:  push(pop() ^ pop()); break;
            case 0xAB:
            {
                int i = pop();
                push(pop() & ~i);
                break;
            }
            case 0xAC:  // IN   membership to bitset
            {   int i = pop();
                int j = pop();
                push(j >= 0 && j < 32 ? (((int) (1L << j) & i) != 0 ? 1 : 0) : 0);
                break;
            }
            case 0xAD:  // BIT  setBIT
            {
                int i = pop();
                if (i < 0 || i >= 32)
                    ipt = 0x4A;
                else
                    push((int) (1L << i));
                break;
            }
            case 0xAE:  // NOT  boolean NOT (not bit per bit!)
                push(pop() == 0 ? 1 : 0);
                break;
            case 0xAF:  // MOD  integer MODulo
            {
                if (sp <= 1)
                    ipt = 0x4C;
                else if (astack[sp-1] == 0)
                {
                    ipt = 0x41; sp--; astack[sp-1] = 0;
                }
                else
                {
                    sp--; astack[sp-1] = imod(astack[sp-1], astack[sp]);
                }
                break;
            }

            case 0xB0:  // DECS  DECriment S register (reverse to ALLOC)
            {
                s -= pop();
                break;
            }

            case 0xB1: // DROP
                pop();
                break;

            case 0xB2: // LODF  reLOaD expr. stack after Function return
            {
                int i = pop();
                restoreStack();
                push(i);
                break;
            }

            case 0xB3: // STORE STORE expr. stack before function call
                if (s + 8 > h)
                {
                    pc--; ipt = 0x40;
                }
                else
                    saveStack();
                break;

            case 0xB4:  // STOFV STOre expr. stack with Formal function Value
                // on top before function call (see: CF)
                if (s + 8 > h) { pc--; ipt = 0x40; }
                else
                {
                    int i = pop();
                    saveStack();
                    mem(s++, i);
                }
                break;

            case 0xB5: // COPT  COPy Top of expr. stack
            {
                int i = pop();
                push(i);
                push(i);
                break;
            }

            case 0xB6:  // CpcOP Character array Parameter COPy
            {
                int i = pop();
                int j = i / 4 + 1;
                if (j > h - s) { push(i); pc--; ipt = 0x40; }
                else if (j < 0)
                    ipt = 0x4A;
                else
                {
                    mem(l + next(), s);
                    i = pop();
                    while (j-- > 0)
                        mem(s++, mem(i++));
                }
                break;
            }

            case 0xB7:  // pcOP  structure Parameter allocate and COPy
            {
                int i = pop();
                int j = i + 1;
                if (j > h - s) { push(i); pc--; ipt = 0x40; }
                else if (j < 0)
                    ipt = 0x4A;
                else
                {
                    mem(l + next(), s);
                    i = pop();
                    while (j-- > 0)
                        mem(s++, mem(i++));
                }
                break;
            }

            case 0xB8: // FOR1  enter  FOR statment
            {
                if (s + 2 > h) { pc--; ipt = 0x40; }
                else
                {
                    int i = next();
                    int hi = pop();
                    int low = pop();
                    int adr = pop();
                    int j = next2() + pc;
                    if (i == 0 && low <= hi || i != 0 && low >= hi)
                    {
                        mem(adr, low);
                        mem(s++, adr);
                        mem(s++, hi);
                    }
                    else
                        pc = j;
                }
                break;
            }

            case 0xB9: // FOR2  end of FOR statment
            {
                int hi  = mem(s-1);
                int adr = mem(s-2);
                int sz  = next();
                int j   = -next2() + pc;
                if ((0x80 & sz) == 1)
                    sz -= 256;
                int i = mem(adr);
                i += sz;
                if (sz >=0 && i > hi || sz <= 0 && i < hi)
                    s -= 2;
                else
                {
                    mem(adr, i);
                    pc = j;
                }
                break;
            }

            case 0xBA: // ENTC Enter CASE
            {
                if (s + 1 > h)
                {
                    pc--; ipt = 0x40;
                }
                else
                {
                    int pc1 = next2();
                    pc += pc1;
                    int j = pop();
                    int low = next2();
                    int hi = next2();
                    int i = pc + 2 * (hi - low) + 4;
                    mem(s++, i);
                    if (j >= low && j <= hi) pc += (j-low+1)*2;
                    int pc2 = next2();
                    pc -= pc2;
                }
                break;
            }

            case 0xBB:  // XIT  eXIT from case or control structure
                s--;
                pc = mem(s);
                break;

            case 0xBC:  // ADDpc  add to program counter
                push(pop() + pc);
                break;

            case 0xBD: // JMP
                pc = pop();
                break;

            case 0xBE: // ORJP   short circuit OR  JumP
                if (pop() != 0)
                {
                    push(1);
                    int pc1 = next();
                    pc += pc1;
                }
                else
                    pc++;
                break;

            case 0xBF: // ANDJP  short circuit AND JumP
                if (pop() == 0)
                {
                    push(0);
                    int pc1 = next();
                    pc += pc1;
                }
                else
                    pc++;
                break;

            case 0xC0: // MOVE   MOVE block
            {
                int sz = pop();
                int j = pop() & ~0xC0000000; // -{30,31}
                int i = pop() & ~0xC0000000; // -{30,31}
                if (sz < 0)
                    ipt = 0x4A;
                else
                {
                    while (sz > 0 && ipt != 3)
                    {
                        mem(i++, mem(j++));
                        sz--;
                        if (memory.isOutOfRange())
                            ipt = 3;
                    }
                }
                break;
            }

            case 0xC1: // CHKNIL check address for NIL
            {
                int i = astack[sp-1];
                if (i == Nil)
                    ipt = 3; // original doc says: 0x41 - I think 3 is better
                break;
            }

            case 0xC2: // LSTA  Load STring Address
                push(mem(g + 1) + next2());
                break;

            case 0xC3: // COMP  COMPare strings
            {
                int i = pop();
                int j = pop();
                var p_a = pmem(i);
                var p_b = pmem(j);
                int pa = 0;
                int pb = 0;
                byte a = (byte) p_a.getValueBytes(pa++, 1);
                byte b = (byte) p_b.getValueBytes(pb++, 1);
                while (a == b && b != 0 && a != 0)
                {
                    a = (byte) p_a.getValueBytes(pa++, 1);
                    b = (byte) p_b.getValueBytes(pb++, 1);
                }
                push(b); push(a); // bug in docs!!!
                break;
            }

            case 0xC4: // GB  Get procedure Base n level down
            {
                int i = l;
                int j = next();
                while (j-- > 0)
                    i = mem(i);
                push(i);
                break;
            }

            case 0xC5: // GB1
                push(mem(l));
                break;

            case 0xC6: // CHK  array boundary CHecK
                if (sp < 3)
                    ipt = 0x4C;
                else
                {
                    int i = astack[sp-3];
                    if (i < astack[sp-2] || i > astack[sp-1])
                        ipt=0x4A;
                    else
                        sp -= 2;
                }
                break;

            case 0xC7: // CHKZ  array boundary CHecK (low=Zero)
                if (sp < 2)
                    ipt = 0x4C;
                else
                {
                    int i = astack[sp-2];
                    if (i < 0 || i > astack[sp-1])
                        ipt=0x4A;
                    else sp--;
                }
                break;

            case 0xC8: // ALLOC ALLOCate block
            {
                int sz = pop();
                if ( s + sz > h) { push(sz); pc--; ipt = 0x40; }
                else { push(s); s += sz; }
                break;
            }

            case 0xC9: // ENTR  ENTeR procedure
            {
                int sz = next();
                if (s + sz > h)
                {
                    pc -= 2; ipt = 0x40;
                }
                else
                    s += sz;
                break;
            }

            case 0xCA: // RTN   ReTurN from procedure
            {
                s = l;
                l = mem(s + 1);
                int i = mem(s + 2);
                pc = i & 0xFFFF;
                if (((1L << ExternalBit) & Integer.toUnsignedLong(i)) != 0)
                {
                    g = mem(s);
                    f = mem(g);
                    pcode = getCode(f);
                }
                break;
            }

            case 0xCB: // NOP
                break;

            case 0xCC: // CX    Call eXternal
                if (s + 4 > h)
                {
                    pc--;  ipt = 0x40;
                }
                else
                {
                    int k = mem(g - next() - 1);
                    int j = k & 0x3FFFFF; // *{0..21}
                    int i = next();
                    mark(g, true);
                    g = mem(j);
                    f = mem(g);
                    pcode = getCode(f);
                    pc = mem(f+i);
                }
                break;

            case 0xCD: // CI    Call procedure at Intermediate level
                if (s + 4 > h)
                {
                    pc--; ipt = 0x40;
                }
                else { int i = next(); mark(pop(), false); pc = mem(f+i); }
                break;

            case 0xCE: // CF    Call Formal procedure
                if (s + 3 > h)
                {
                    pc--; ipt = 0x40;
                }
                else
                {
                    s--;
                    int i = mem(s);
                    mark(g, true);
                    int j = (i >> 24) & 0xFF;
                    i = i & 0xFFFFFF; // *{0..23};
                    g = mem(i);
                    f = mem(g);
                    pcode = getCode(f);
                    pc = mem(f + j);
                }
                break;

            case 0xCF: // CL    Call Local procedure
                if (s + 4 > h)
                {
                    pc--; ipt = 0x40;
                }
                else
                {
                    int i = next(); mark(l, false); pc = mem(f + i);
                };
                break;

            case 0xD0:  case 0xD1:  case 0xD2:  case 0xD3:
            case 0xD4:  case 0xD5:  case 0xD6:  case 0xD7:
            case 0xD8:  case 0xD9:  case 0xDA:  case 0xDB:
            case 0xDC:  case 0xDD:  case 0xDE:  case 0xDF:
                if (s + 4 > h)
                {
                    pc--;
                    ipt = 0x40;
                }
                else
                {
                    mark(l, false);
                    pc = mem(f + (ir & 0xF));
                }
                break;

            case 0xE0:  // INCL
            {
                int i = pop();
                int j = pop() + (i >> 5);
                i = i & 0x1F;
                mem(j, mem(j) | ((int)(1L << i)));
                break;
            }

            case 0xE1:  // EXCL
            {
                int i = pop();
                int j = pop() + (i >> 5);
                i = i & 0x1F;
                mem(j, mem(j) & ~((int) (1L << i)));
                break;
            }

            case 0xE2:  // INL  membership IN Long set
            {
                int k = pop();
                int j = pop();
                int i = pop();
                if (i < 0 || i >= k)
                    push(0);
                else
                    push( ((int) (1L << (i & 0x1F)) & mem(j + (i >> 5))) != 0 ? 1 : 0);
                break;
            }

            case 0xE3:  // QUOT
            {
                quote(next());
                break;
            }


            case 0xE4: // INC1  INCrement by 1
            {   int i = pop(); mem(i, mem(i) + 1);
                break;
            }

            case 0xE5: // DEC1  DECrement by 1
            {   int i = pop(); mem(i, mem(i) - 1);
                break;
            }

            case 0xE6: // INC   INCrement
            {   int i = pop(); int j = pop(); mem(j, mem(j) + i);
                break;
            }

            case 0xE7: // DEC   DECrement
            {
                int i = pop(); int j = pop(); mem(j, mem(j) - i);
                break;
            }

            case 0xE8: // STOT  STOre Top on proc stack
                if (s + 1 > h)
                {
                    pc--; ipt = 0x40;
                }
                else
                    mem(s++, pop());
                break;

            case 0xE9: // LODT  LOaD   Top of proc stack
                push(mem(--s));
                break;

            case 0xEA: // LXA   Load indeXed Address
            {
                int sz = pop();
                int i = pop();
                push(pop() + i * sz);
                break;
            }

            case 0xEB:  // Lpc   Load Procedure Constant
            {
                int i = next();
                int j = next();
                i = mem(g - i - 1);
                //((byte*)&i)[3] = (byte)j;
                i = Conversion.byteArrayToInt(new byte[]{(byte) j}, 0, i, 3 * 8, 1); //dstPos in bits
                push(i);
                break;
            }

            case 0xEC: // BBU  Bit Block Unpack
            {
                int sz = pop();
                if (sz < 1 || sz > 32)
                {
                    push(sz);
                    pc--;
                    ipt = 0x4A;
                }
                int i = pop();
                int adr = pop();
                push(memory.bbu(adr, i, sz));
                break;
            }

            case 0xED: // BBP  Bit Block Pack
            {
                int j  = pop();
                int sz = pop();
                if (sz < 1 || sz > 32)
                {
                    push(sz);
                    pc--;
                    ipt = 0x4A;
                }
                int i = pop();
                int adr = pop();
                memory.bbp(adr, i, sz, j);
                break;
            }

            case 0xEE: // BBLT Bit BLock Transfer
            {
                int sz = pop();
                int i = pop();
                int j = pop();
                int a = pop();
                int b = pop();
                bitblt(b, a, j, i, sz);
                break;
            }

            case 0xEF: // PDX Prepare Dynamic indeX
            {
                int i = pop(); /* index */
                int j = pop(); /* desc. address */
                int k = mem(j);  /* address */
                j = mem(j + 1); /* length  */
                push(k);
                push(i);
                if (i < 0 || i > j)
                    ipt = 0x4A;
                break;
            }

            case 0xF0: // SWAP
            {   int i = pop(); int j = pop(); push(i); push(j);
                break;
            }

            case 0xF1: // LPA Load Parameter Address
                push(l - next() - 1);
                break;

            case 0xF2: // LPW Load Parameter WORD
                push(mem(l - next() - 1));
                break;

            case 0xF3: // SPW Store Parameter WORD
                mem(l - next() - 1, pop());
                break;

            case 0xF4: // SSWU Store Stack Word Undestructive
            {   int i = pop();
                mem(pop(),  i); push(i);
                break;
            }

            case 0xF5: // RCHK  range CHecK
            {
                int i = pop(); int j = pop(); int k = pop();
                if (k >= j && k <= i)
                    push(1);
                else
                    push(0);
                break;
            }

            case 0xF6: // RCHZ range check (low=Zero)
            {
                int i = pop(); int k = pop();
                if (k >= 0 && k <= i) push(1); else push(0);
                break;
            }


            case 0xF7: // CM Call procedure from dynamic Module
            {
                if (s + 4 <= h)
                {
                    int i = next();
                    s--;
                    int j = mem(s);
                    mark(g, true);
                    g = j;
                    f = mem(g);
                    pc = mem(f + i);
                }
                else
                {
                    pc--;
                    ipt = 0x40;
                }
                break;
            }

            case 0xF8: // CHKBX  CHecK BoX
            {
                int p0 = pop();
                int p1 = pop();
                int x00 =  mem(p0)      % 0x10000;
                int y00 = (mem(p0)<<16) % 0x10000;
                p0++;
                int x01 =  mem(p0)      % 0x10000;
                int y01 = (mem(p0)<<16) % 0x10000;
                int x10 =  mem(p1)      % 0x10000;
                int y10 = (mem(p1)<<16) % 0x10000;
                p1++;
                int x11 =  mem(p1)      % 0x10000;
                int y11 = (mem(p1)<<16) % 0x10000;
                push(x10 <= x01 && y10 <= y01 && x00 <= x11 && y00 <= y11 ? 1 : 0);
                break;
            }

            case 0xF9:  // bmg
                bmg(next());
                break;

            case 0xFA:  // active
                push(p);
                break;


            case 0xFB: // USR User defined functions
            {
                int op = next();
                switch (op)
                {
                    case 0:
                    {
                        // str: ARRAY OF CHAR
                        int len = pop();
                        //unused(len);
                        //const byte* psz = (const byte*)&mem[pop()]; //TODO byte*
                        //printf("%s\n", psz);
                        //trace("%s\n", psz);
                        break;
                    }
                    default:
                        ipt = 0x7;
                        break;
                }
                break;
            }

            case 0xFC:
                switch (next())
                {
                    case 0x0: // cpu vers. */
                        push(7); break;
                    case 0x1:
                        System.out.printf ("\n%08X\n", pop()); break;
                    case 0x2: // microcode vers.
                        push(2); break;
                    default:
                        pc--; ipt = 7;
                }
                break;

            case 0xFD: // NII Never Implemented Instruction
                ipt = 0x7;
                break;

            case 0xFE:
            {
                int i = pop();
                System.out.printf("%08X\n", i);
                //trace("%08X\n", i);
                break;
            }

            case 0xFF:
                ipt = 0x49;
                break;

            default:
                ipt = 0x7;
                break;
        }

        if (ipt == 0 && s > h || s == 0)
        {
            throw new RuntimeException();
        }
        return false;
    }

    private void stop() {
        saveRegisters();
    }

    public void start() {
        bDebug = false;
        ipt = 0;
        sp = 0;
        p = mem(1);
        restoreRegisters();
        stepIdx = 0;
    }

    private void clearStack() {
        for (int t = sp; t < AStackSize; t++){
            astack[t] = null;
        }
    }

    private boolean debugMonitor(int a) {
        return true;
    }

    private void bmg(int op) {
        switch (op)
        {
            case 0: { // in rectangle
                int h = pop();
                int w = pop();
                int y = pop();
                int x = pop();
                push(inrect(x, y, w, h));
                break;
            }

            case 1: { // vertical line
                int len = pop();
                int y = pop();
                int x = pop();
                //Bitmap* bmp = (Bitmap*)(byte*)&mem[pop()];
                int mode = pop();
                //vline(mode, bmp, x, y, len);
                break;
            }

            case 2: { // bitblit
                int nobits = pop();
                int sofs   = pop();
                int sou    = pop();
                int dofs   = pop();
                int dst    = pop();
                int mode = pop();
                //gbblt(mode, dst, dofs, sou, sofs, nobits);
                break;
            }

            case 3: { // display character
                int ch  = pop();
                //Font* font = (Font*)(byte*)&mem[pop()];
                int y = pop();
                int x = pop();
                //Bitmap* bmp = (Bitmap*)(byte*)&mem[pop()];
                int mode = pop();
                //dch(mode, bmp, x, y, font, ch);
                break;
            }

            case 4: { // clip
                int h = pop();
                int w = pop();
                //Clip* clp = (Clip*)(byte*)&mem[pop()];
                //push(clip(clp, w, h));
                break;
            }


            case 5: { // line
                int y1 = pop();
                int x1 = pop();
                int y = pop();
                int x = pop();
                //Bitmap* bmp = (Bitmap*)(byte*)&mem[pop()];
                int mode = pop();
                //line(mode, bmp, x, y, x1, y1);
                break;
            }

            case 6: { // circle
                int y = pop();
                int x = pop();
                //Circle* ctx = (Circle*)(byte*)&mem[pop()];
                //Bitmap* bmp = (Bitmap*)(byte*)&mem[pop()];
                int mode = pop();
                //circle(mode, bmp, ctx, x, y);
                break;
            }

            case 7: { // arc
                //ArcCtx* ctx = (ArcCtx*)(byte*)&mem[pop()];
                //Bitmap* bmp = (Bitmap*)(byte*)&mem[pop()];
                int mode = pop();
                //arc(mode, bmp, ctx);
                break;
            }


            case 8: { // filled triangle
                //TriangleFilled* ctx = (TriangleFilled*)(byte*)&mem[pop()];
                //trif(ctx);
                break;
            }
            case 9: { // filled circle
                //CircleFilled* ctx = (CircleFilled*)(byte*)&mem[pop()];
                //circlef(ctx);
                break;
            }
            default:
                pc--; ipt = 7;
        }
    }

    private int inrect(int x, int y, int w, int h) {
        // x <= w and y <= h is not a bug. This is how ucode was written!
        // BMG.m takes this into account
//  trace("inrect(%d, %d, %d, %d)=%d\n", x, y, w, h, x >= 0 && x <= w && y >= 0 && y <= h);
        return x >= 0 && x <= w && y >= 0 && y <= h ? 1 : 0;
    }

    private void bitblt(int b, int a, int j, int i, int sz) {
       //if (bits < 0 || dofs < 0 || sofs < 0)
       //{
       //    Ipt = 0x4A;
       //    return;
       //}
       //dword  test = mem[dst]
       //        | mem[src]
       //        | mem[dst + ((dofs + bits + 31) >> 5)]
       //        | mem[src + ((sofs + bits + 31) >> 5)];
       //unused(test);
       //if (mem.OutOfRange())
       //{
       //    Ipt = 3;
       //    return;
       //}
       //dword* pdst = (dword*)(const byte*)&mem[dst + (dofs >> 5)];
       //dword* psrc = (dword*)(const byte*)&mem[src + (sofs >> 5)];
       //bitBlt(pdst, dofs & 0x1F, psrc, sofs & 0x1F, bits);
        throw new NotImplementedException();
    }

    private void quote(int op) {
        // X MOD N = X - (X QOU N) * N
        switch (op)
        {
            case 0: // SHRQ ??? (not tested) probably used by Portable C Compiler only
                if (sp <= 1)
                    ipt = 0x4C;
                else
                {
                    sp--; astack[sp-1] = (int) ( (long)astack[sp-1] >> (long) astack[sp]) ;
                }
                break;
            case 1: // QUOT
                if (sp <= 1)
                    ipt = 0x4C;
                else
                {
                    sp--; astack[sp-1] /= astack[sp];
                }
                break;
            case 2: // ANDQ ??? (not tested) probably used by Portable C Compiler only
                if (sp <= 1)
                    ipt = 0x4C;
                else
                {
                    sp--; astack[sp-1] &= ((1 << astack[sp]) - 1);
                }
                break;
            case 3: // REM
                if (sp <= 1)
                    ipt = 0x4C;
                else
                {
                    sp--; astack[sp-1] %= astack[sp];
                }
                break;
            default:
                ipt = 7;
                pc -= 2;
                break;
        }
    }

    private void mark(int x, boolean extern) {
        int i = s;
        mem(s++, x);
        mem(s++, l);
        if (extern)
            mem(s, (int) ((long) pc | (1L << ExternalBit)));
        else
            mem(s, pc);
        s += 2;
        l = i;
    }

    private VirtualMemory.VirtualMemoryPointer getCode(int f) {
        if (f < 0 || f > memory.getSize())
            ipt = 3;
        return pmem(f % memory.getSize());
    }

    private void saveStack() {
        int i = s;
        while (sp != 0) mem(s++, pop());
        mem(s,  s - i);
        s++;
    }

    private void restoreStack() {
        int i = mem(--s);
        if (i > AStackSize)
        {
            ipt = 0x4C;
            i = AStackSize;
        }
        while (i-- > 0)
            push(mem(--s));
    }

    private int imod(int x, int y) {
        var ret = _idiv(x, y);
        return ret.getRight();
    }

    private void fpu() {
        VirtualMemory.FI x = new VirtualMemory.FI(new VirtualMemory.U(0, 0));
        VirtualMemory.FI y = new VirtualMemory.FI(new VirtualMemory.U(0, 0));
        switch (ir)
        {
            case 0x98:  case 0x99:  case 0x9A:  case 0x9B:  case 0x9C:
            y.u.setI(pop());
            x.u.setI(pop());
            break;
            case 0x9D:  case 0x9E:
            x.u.setI(pop());
            break;
        }
        switch (ir)
        {
            case 0x98:  x.u.setF(x.u.getF() + y.u.getF()); push(x.u.getI()); break;
            case 0x99:  x.u.setF(x.u.getF() - y.u.getF()); push(x.u.getI()); break;
            case 0x9A:  x.u.setF(x.u.getF() * y.u.getF()); push(x.u.getI()); break;
            case 0x9B:  x.u.setF(x.u.getF() / y.u.getF()); push(x.u.getI()); break;
            case 0x9C:
                if      (x.u.getF() > y.u.getF()) { push(1); push(0); }
                else if (x.u.getF() < y.u.getF()) { push(0); push(1); }
                else { push(0); push(0); }
                break;

            case 0x9D:
                if (x.u.getF() < 0)
                    x.u.setF(-x.u.getF());
                push(x.u.getI());
                break;
            case 0x9E:
                x.u.setF(-x.u.getF());
                push(x.u.getI());
                break;
            case 0x9F:
            {
                switch (next())
                {
                    case 0x0:   x.u.setF((float) pop()); push(x.u.getI()); break;
                    case 0x1:   x.u.setI(pop()); push((int) x.u.getF()); break;
                    default:    ipt = 7; pc--; break;
                }
            }
        }
    }

    private void bitmove(int dst, int _dofs, int src, int _sofs, int bits) {
        throw new NotImplementedException();
    }

    private void mmem(int idx, int length, byte[] block) {
        throw new NotImplementedException();
    }

    private byte[] mmem(int idx, int length) {
        throw new NotImplementedException();
    }

    private void io(int no) {
        //log.info("step {}, io {}", stepIdx, String.format("%x", no));
        switch (no) {
            case 0x0: { //input
                int adr = pop();
                int ioAddr = adr & 0xFFC;
                if (ioAddr == console.getAddress()) { // console ipt 0x0C
                    push(console.inp(adr));
                } else {
                    Integer inp = serial.inp(no, ioAddr, adr);
                    if (inp != null) {
                        push(inp);
                    } else {
                        ipt = 3;
                        push(0);
                    }
                    //throw new NotImplementedException(String.format("in %x %x", no, ioAddr));
                }
                break;
            }
            case 0x1: { //output
                int i = pop();
                int adr = pop();
                int ioAddr = adr & 0xFFC;
                if (ioAddr == console.getAddress()) {
                    console.out(adr, i);
                } else {
                    serial.out(no, ioAddr, adr, i);
                    //throw new NotImplementedException(String.format("out %x %x", no, ioAddr));
                }
                break;
            }
            case 0x2: { //disk io
                int len = pop();    // bytes
                int adr = pop();    // address
                int sec = pop();    // sector
                int dsk = pop();    // disk
                int op = pop();    // operation
                push(doDiskOperation(op, dsk, sec, adr, len));
                break;
            }
            case 0x3: {
                log.info("{}", String.format("%c", pop()));
                break;
            }
            case 0x4: {
                ipt = 7;  pc -= 2;
                break;
            }
            default:
                log.info("unsupported i/o function {}", String.format("%03X", no));
                ipt = 7;  pc -= 2;
                //break;
                //throw new NotImplementedException(String.format("unknown io channel %x", no));
            }
    }

    private int doDiskOperation(int op, int dsk, int sec, int adr, int len) {
        switch (op)
        {
            case 1:
                if (dsk >= 0 && dsk < disks.size()) {
                    if (disks.get(dsk).isMounted()){
                        //do nothing
                    }
                    disks.get(dsk).setMounted(true);
                    return 1;
                }
                return 0;
            case 2:
                if (dsk >= 0 && dsk < disks.size()) {
                    if (!disks.get(dsk).isMounted()){
                        //do nothing
                    }
                    disks.get(dsk).setMounted(false);
                    return 1;
                }
                return 0;
            case 3:
                if (dsk >= 0 && dsk < disks.size()) {
                    var ret = pmem(adr);
                    ret.setValue(disks.get(dsk).getSize4Kb());
                    return 1;
                }
                return 0;
            case 4:
                if (dsk >= 0 && dsk < disks.size()) {
                    var ret = pmem(adr);
                    byte[] data = disks.get(dsk).read(sec * 512, len);
                    ret.setValues(data);
                    return data.length == len ? 1 : 0;
                }
                return 0;
            case 5:
                if (dsk >= 0 && dsk < disks.size()) {
                    //return Disks.Write(dsk, sec, &mem[adr], len);
                }
                throw new NotImplementedException();
                //return 0;
            case 6: {
                var now = LocalDateTime.now();
                mem(adr++, now.getYear());
                mem(adr++, now.getMonth().getValue());
                mem(adr++, now.getDayOfMonth());
                mem(adr++, now.getHour());
                mem(adr++, now.getMinute());
                mem(adr++, now.getSecond());
                return 1;
            }
            case 8: // getspecs
                if (dsk >= 0 && dsk < disks.size()) {
                    //var p_spec = pmem(adr);
                    //p_spec.setValues(disks.get(dsk).getSpecs().asBytes());

                }
                return 0;
            case 9: // setspecs
                if (dsk >= 0 && dsk < disks.size()) {

                }
                //throw new NotImplementedException();
                return 1;
                //return Disks.SetSpecs(dsk, (Request*)(byte*)&mem[adr]);
            default:
                //trace("invalid disk operation: %d\n", op);
                //throw new NotImplementedException();
                return 0;
        }
    }

    long qabs(long x) { return x >= 0 ? x : -x; }

    Pair<Integer, Integer> _idiv(long x, long y)
    {
        //assert(y != 0);
        long z  = 0;
        long bt = 1;
        while (qabs(x) > qabs(y))
        {
            bt = bt << 1;
            y  = y << 1;
        };
        for (;;)
        {
            if ((x >= 0) == (y >= 0))
            {
                if (y < 0)
                {
                    if (x <= y) { x = x - y;    z = z + bt; }
                }
                else
                {
                    if (x >= y) { x = x - y;    z = z + bt; }
                }
            }
            else
            {
                if (y < 0)
                {
                    if (x > 0) { x = x + y;     z = z - bt; }
                }
                else
                {
                    if (x < 0) { x = x + y;     z = z - bt; }
                }
            }
            if (bt == 1)
                break;
            bt = bt >> 1;
            if (y > 0)
                y = (y & ~0x1) >> 1;
            else
                y = (y | 0x1) >> 1;
        }
        return Pair.of((int)z, (int)x);
    }

    private int idiv(int x, int y) {
        int rem = 0;
        var ret =  _idiv(x, y);
        rem = ret.getRight();
        return ret.getLeft();
    }

    private void transfer(int p_to, int p_from) {
        int i = mem(p_to);
        //log.info("step {} transfer from {} to {} ", stepIdx, String.format("%x", p), String.format("%x", i));
        mem(p_from, p);
        saveRegisters();
        p = i;
        restoreRegisters();
    }

    private int pop() {
        if (sp > 0)
            return astack[--sp];
        ipt = 0x4C;
        return 0;
    }

    /*
     * int of four byte
     */
    private int next4() {
        int pc = this.pc;
        this.pc += 4;
        return code(pc, 4);
    }

    /*
     * int of two byte
     */
    private int next2() {
        int pc = this.pc;
        this.pc += 2;
        return code(pc, 2);
    }

    /*
    * int of one byte
     */
    private int next() {
        return code(pc++);
    }

    private void push(int w) {
        if (sp >= 0 && sp < AStackSize)
            astack[sp++]=w;
        else
            ipt = 0x4C;
    }

    private int mem(int idx) {
        return memory.getPointer(idx).getValue();
    }

    private void mem(int idx, int val) {
        memory.getPointer(idx).setValue(val);
    }

    private int code (int idx) {
        return code(idx, 1);
    }

    private int code(int idx, int n) {
        return pcode.getValueBytes(idx, n);
    }

    private void trap(int no) {
        //  trace("Trap %02.2X\n", no);
        //log.info("step {}, trap {}", stepIdx, String.format("%x", no));
        //  xxx: (only for debuging emulator itself.
        if (no == 7)
            bDebug = true;

        if (no >= 0x3F)
        {
            mem(p + 6,  no);
            no = 0x3F;
        }
        if (no == 0)
        {
            trap(6);
            return;
        }
        if (no >= 0xC && no < 0x3F && (m & 0x1) == 0)
            return;
        if (no >= 2 && no < 0xC)
        {
            mem(p + 6, no);
            if ((m & (int) (1L << Integer.toUnsignedLong(no))) == 0)
            {
                if (no != 3) // booter use Ipt 3 to determine memory size
                {
                    //log.error("Unexpected interrupt {}.\n", no);
                    bDebug = true;
                }
                return;
            }
        }
        if (no == 1  && (m & 0x2) == 0)
            return;
        if (no == 0x3F && (m & (int) (1L << 31)) == 0)
            return;
        transfer(no*2, mem(no * 2 + 1));
    }

    private void restoreRegisters() {
        mem(0, p);
        g = mem(p);
        f = mem(g);
        pcode = getCode(f);
        l  = mem(p+1);
        pc = mem(p+2);
        m  = mem(p+3);
        s  = mem(p+4);
        h  = mem(p+5);
        h -= AStackSize + 1;
        restoreStack();
    }

    private void saveRegisters() {
        mem(1, p);
        saveStack();
        mem(p, g);
        mem(p + 1, l);
        mem(p + 2, pc);
        mem(p + 3, m);
        mem(p + 4, s);
    }

    public void runSafe() {
        try {
            run();
        } catch (Exception e) {
            stopTimer();
            throw new RuntimeException(e);
        }
    }

    public void patch(int ir) {
        patch(pc, ir);
    }

    public void patch(int pc, int ir) {
        patch(pc, 1, new byte[]{(byte) ir});
    }

    public void patch(int pc, int len, byte[] data) {
        pcode.setValueBytes(pc, len, data);
    }

    public int getAtStack() {
        if (sp <= 0) {
            throw new IllegalStateException();
        }
        Integer top = astack[sp - 1];
        if (top == null)
            throw new IllegalStateException();
        return top;
    }

    public static class VirtualMachineStepDump {

        private final Logger log = LoggerFactory.getLogger(this.getClass());

        private final long stepIdx;
        int memorySizeBytes;

        private int
                ipt, ipts,
                sp, sps,
                pc,                pcs,
                ir, irs,
                p, ps,
                l, ls,
                g, gs,
                m, ms,
                h, hs,
                s, ss,
                f, fs;
        private byte[] memory;
        boolean dumpMem = false;

        private Integer[] astack;
        private Integer[] astackOld;
        private Map<Pair<Integer, Pair<Integer, Integer>>, byte[]> memoryDiff = new ListOrderedMap<>();

        public VirtualMachineStepDump(VirtualMachine machine) {
            this.stepIdx = machine.stepIdx;
            this.astack = new Integer[AStackSize];
            this.astackOld = new Integer[AStackSize];
            this.memorySizeBytes = machine.memory.getSize() * 4;

            if (dumpMem) {
                memory = new byte[memorySizeBytes];
                System.arraycopy(machine.memory.data, 0, memory, 0, memory.length);
            }
            for(int s = 0; s < AStackSize; s++) {
                this.astackOld[s] = machine.astack[s];
            }
            ipts = machine.ipt;
            sps = machine.sp;
            pcs = machine.pc;
            irs = machine.ir;
            ps = machine.p;
            ls = machine.l;
            gs = machine.g;
            ms = machine.m;
            hs = machine.h;
            ss = machine.s;
            fs = machine.f;
        }

        public void dump(VirtualMachine machine) {
            for(int s = 0; s < AStackSize; s++) {
                this.astack[s] = machine.astack[s];
            }

            if (dumpMem) {
                int m0 = 0;
                do {
                    int m1 = Arrays.mismatch(memory, m0, memorySizeBytes, machine.memory.data, m0, memorySizeBytes);
                    if (m1 >= 0) {
                        m0 += m1;
                        memoryDiff.put(Pair.of(m0, Pair.of(m0 / 4, m0 % 4)), new byte[]{memory[m0], machine.memory.data[m0]});
                        m0++;
                    } else {
                        m0 = -1;
                    }
                } while (m0 >= 0);
            }
            memory = null;
            ipt = machine.ipt;
            sp = machine.sp;
            pc = machine.pc;
            ir = machine.ir;
            p = machine.p;
            l = machine.l;
            g = machine.g;
            m = machine.m;
            h = machine.h;
            s = machine.s;
            f = machine.f;
            if (!memoryDiff.isEmpty()) {
                log.info("step {}, {} bytes changed", stepIdx, memoryDiff.size());
            }
            if (machine.trace != null) {
                var traceStep = machine.trace.getSteps().get(stepIdx);
                if (traceStep != null) {
                    if (traceStep.getIr() != ir) {
                        throw new RuntimeException(String.format("trace doesn't match %d", stepIdx));
                    }
                    machine.trace.getSteps().remove(stepIdx);
                } else if (machine.trace.getSteps().isEmpty()){
                    throw new RuntimeException("no trace");
                }
            }
        }

        @Override
        public String toString() {
            return String.format("#%d: %s [0x%02X], PC %d->%d, IPT %d->%d, SP %d->%d, module MPG[%d->%d, %d->%d, %,d->%d] code LFHS[%d->%d, %d->%d, %d->%d, %d->%d], astack [%s]->[%s]", stepIdx, MCODES.get(ir),  ir, pcs, pc, ipts, ipt, sps, sp, ms, m, ps, p, gs, g, ls, l, fs, f, hs, h, ss, s,
                    Arrays.stream(astackOld).filter(Objects::nonNull).map(v -> String.format("%d", v)).collect(Collectors.joining(", ")),
                    Arrays.stream(astack).filter(Objects::nonNull).map(v -> String.format("%d", v)).collect(Collectors.joining(", "))
            );
        }
    }
}
