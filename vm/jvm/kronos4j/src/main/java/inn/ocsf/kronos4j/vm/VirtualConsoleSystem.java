package inn.ocsf.kronos4j.vm;

import org.apache.commons.lang3.NotImplementedException;
import org.jline.terminal.Terminal;
import org.jline.terminal.TerminalBuilder;
import org.jline.utils.NonBlockingReader;
import java.io.PrintStream;

import java.io.IOException;
import java.io.UnsupportedEncodingException;
import java.nio.charset.StandardCharsets;

public class VirtualConsoleSystem implements VirtualConsole {
    private static final int EMPTY_CHAR = 512;

    private final int address;
    private final int ipt;
    private boolean outIptEnabled = false;
    private boolean inpIptEnabled = false;
    private int inChar;
    private final NonBlockingReader reader;

    public VirtualConsoleSystem(int address, int ipt) throws IOException {
        this.address = address;
        this.ipt = ipt;
        inChar = EMPTY_CHAR;
        Terminal terminal = TerminalBuilder.builder().jna(true).system(true).build();
        terminal.enterRawMode();
        reader = terminal.reader();
    }

    // Создаем отдельный поток вывода, который СТРОГО форсирует UTF-8 наружу
    private static final PrintStream outUtf8 = new PrintStream(System.out, true, StandardCharsets.UTF_8);

    public static void printGuestChar(int value) {
        // 1. Стандартный ASCII (латиницу и управляющие) выводим как обычно
        if (value <= 127) {
            outUtf8.print((char) value);
            return;
        }

        try {
            // 2. Однобайтовый кириллический байт Кроноса
            byte[] singleByte = new byte[]{(byte) value};

            // Честно переводим KOI8-R байт в универсальную Java-строку (Unicode)
            String decodedStr = new String(singleByte, "KOI8-R");

            // Выводим строку через наш UTF-8 поток
            outUtf8.print(decodedStr);
        } catch (UnsupportedEncodingException e) {
            // Фолбэк на случай непредвиденных сбоев
            outUtf8.print((char) value);
        }
    }

    @Override
    public int inp(int addr) {
        switch (addr & 0x0003) {
            case 0:
                if (inChar == EMPTY_CHAR) {
                    inChar = busyRead();
                }
                return (inpIptEnabled ? 0100 : 0) | (inChar != EMPTY_CHAR ? 0200 : 0);
            case 1:
            {
                if (inChar == EMPTY_CHAR) {
                    inChar = busyRead();
                }
                int data = inChar == EMPTY_CHAR ? 0 : inChar;
                inChar = EMPTY_CHAR;

                return data & 0xFF;
            }
            case 2:
                return 0200 | (outIptEnabled ? 0100 : 0); //0b1000_0000 | (outIptEnabled ? 0b0100_0000 : 0);
            case 3:
                return 0;
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
            case 3: printGuestChar(value); break; //System.out.print((char)value);             break;
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
        if (inChar == EMPTY_CHAR) {
            inChar = busyRead();
        }
        return inpIptEnabled && inChar != EMPTY_CHAR;
    }

    private int busyRead() {
        int res = EMPTY_CHAR;
        try {
            int ret = -1;
            if (reader.ready()) {
                ret = reader.read(1);
            }
            switch (ret) {
                case NonBlockingReader.EOF, NonBlockingReader.READ_EXPIRED -> {
                    //do nothing
                }
                default -> res = ret;
            }
        } catch (IOException e) {
            throw new RuntimeException(e);
        }
        return res;
    }
}
