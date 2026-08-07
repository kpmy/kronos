package inn.ocsf.kronos4j.vm;

import org.apache.commons.io.FileUtils;

import java.io.IOException;
import java.nio.file.Path;

public class VirtualDisk {

    private byte[] cache;

    private VirtualDisk() {

    }

    public static VirtualDisk attach(Path diskPath) throws IOException {
        var ret = new VirtualDisk();
        ret.cache = FileUtils.readFileToByteArray(diskPath.toFile());
        return ret;
    }

    public byte[] read(int offset, int length) {
        var ret = new byte[length];
        System.arraycopy(cache, offset, ret, 0, length);
        return ret;
    }
}
