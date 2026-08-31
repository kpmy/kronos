package inn.ocsf.kronos4j.vm;

public interface VirtualConsole {
    int inp(int addr);

    void out(int addr, int value);

    int getAddress();

    int getIpt();

    boolean isOutIptEnabled();

    boolean isInpIptEnabled();
}
