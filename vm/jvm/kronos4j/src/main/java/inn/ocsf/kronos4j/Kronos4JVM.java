package inn.ocsf.kronos4j;

import inn.ocsf.kronos4j.vm.VirtualDisk;
import inn.ocsf.kronos4j.vm.VirtualMachine;
import org.apache.commons.configuration2.PropertiesConfiguration;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Arrays;

public class Kronos4JVM {

    public static final int MEMORY_SIZE = 4 * 1024 * 1024; // 4 megabytes

    public static final Logger LOG =  LoggerFactory.getLogger(Kronos4JVM.class);

    public static void main(String[] args) throws InterruptedException {
        VirtualMachine vm = new VirtualMachine(MEMORY_SIZE);
        PropertiesConfiguration config = new PropertiesConfiguration();
        addDisks(vm, config);
        if (vm.getDiskCount() > 0) {
            readBooter(vm);
        }
        vm.run();
    }

    private static void readBooter(VirtualMachine vm) {
        VirtualDisk disk = vm.getDisk(0);
        var boot = disk.read(0, 4096);
        vm.getMemory().store(0, 4096, boot);
    }

    private static void addDisks(VirtualMachine vm, PropertiesConfiguration config) {
        var diskPathStrings = config.getStringArray("kronos.vm.disks");
        Arrays.stream(diskPathStrings).map(Paths::get).forEach(path -> {
            if (Files.exists(path) && Files.isRegularFile(path)) {
                try {
                    vm.addDisk(VirtualDisk.attach(path));
                } catch (IOException e) {
                    throw new RuntimeException(e);
                }
            } else {
                LOG.error("The disk {} not found", path);
            }
        });
    }
}
