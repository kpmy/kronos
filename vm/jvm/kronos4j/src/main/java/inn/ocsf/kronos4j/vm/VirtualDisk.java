package inn.ocsf.kronos4j.vm;

import org.apache.commons.io.FileUtils;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

public class VirtualDisk {

    private Path diskPath;
    private byte[] cache;
    private boolean mounted;

    private VirtualDisk() {

    }

    public static VirtualDisk attach(Path diskPath) throws IOException {
        var ret = new VirtualDisk();
        ret.diskPath = diskPath;
        ret.cache = FileUtils.readFileToByteArray(diskPath.toFile());
        return ret;
    }

    public byte[] read(int offset, int length) {
        var ret = new byte[length];
        System.arraycopy(cache, offset, ret, 0, length);
        return ret;
    }

    public boolean isMounted() {
        return mounted;
    }

    public void setMounted(boolean mounted) {
        this.mounted = mounted;
    }

    public int getSize4Kb() {
        try {
            return (int) Files.size(diskPath) / (4 * 1024);
        } catch (IOException e) {
            throw new RuntimeException(e);
        }
    }
}
