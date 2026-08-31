package inn.ocsf.kronos4j.vm;

import org.apache.commons.io.FileUtils;

import java.io.BufferedWriter;
import java.io.ByteArrayOutputStream;
import java.io.DataOutputStream;
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

    public VirtualDiskSpecs getSpecs() {
        var pRequest = new VirtualDiskSpecs();
        long SectorsPerCluster = 0;
        long BytesPerSector = 0;
        long TotalNumberOfClusters = 0;
        //only for floppy
        long TotalNumberOfSectors = TotalNumberOfClusters * SectorsPerCluster;
        long TotalNumberOfBytes = TotalNumberOfSectors * BytesPerSector;
        if((pRequest.maxsec - pRequest.minsec + 1) * BytesPerSector  * pRequest.cyls * pRequest.heads == TotalNumberOfBytes) {
            //ok
        } else {
            throw new IllegalStateException("wrong disk specs");
        }
        return pRequest;
    }

    public class VirtualDiskSpecs {
        private int op;
        private int drn;
        private int res;
        private int dmode;
        private int dsecs; // device size in secs
        private int ssc;   // 2**ssc = secsize
        private int secsize;
        private int cyls;
        private int heads;
        private int minsec;
        private int maxsec;
        private int ressec;  // reserved sectors (ice booter in 2.5)
        private int precomp; // precompensation
        private int rate; // heads stepping

        public byte[] asBytes() {
            var ret = new ByteArrayOutputStream();
            var buf = new DataOutputStream(ret);

            return ret.toByteArray();
        }
    }
}
