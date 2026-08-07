package inn.ocsf.kronos4j;

import inn.ocsf.kronos4j.vm.VirtualDisk;
import inn.ocsf.kronos4j.vm.VirtualMachine;
import org.apache.commons.configuration2.Configuration;
import org.apache.commons.configuration2.FileBasedConfiguration;
import org.apache.commons.configuration2.PropertiesConfiguration;
import org.apache.commons.configuration2.builder.FileBasedConfigurationBuilder;
import org.apache.commons.configuration2.builder.fluent.Configurations;
import org.apache.commons.configuration2.builder.fluent.Parameters;
import org.apache.commons.configuration2.convert.DefaultListDelimiterHandler;
import org.apache.commons.configuration2.ex.ConfigurationException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Arrays;

public class Kronos4JVM {

    public static final int MEMORY_SIZE = 4 * 1024 * 1024; // 4 megabytes

    public static final Logger LOG =  LoggerFactory.getLogger(Kronos4JVM.class);

    public static void main(String[] args) throws InterruptedException, ConfigurationException {
        VirtualMachine vm = new VirtualMachine(MEMORY_SIZE);
        Parameters params = new Parameters();
        FileBasedConfigurationBuilder<FileBasedConfiguration> builder =
                new FileBasedConfigurationBuilder<FileBasedConfiguration>(PropertiesConfiguration.class)
                        .configure(params.properties()
                                .setListDelimiterHandler(new DefaultListDelimiterHandler(','))
                                .setFileName("application.properties"));
        Configuration config = builder.getConfiguration();
        addDisks(vm, config);
        if (vm.getDiskCount() > 1) {
            readBooter(vm, 1);
        }
        vm.run();
    }

    private static void readBooter(VirtualMachine vm, int diskIndex) {
        VirtualDisk disk = vm.getDisk(diskIndex);
        var boot = disk.read(0, 4096);
        vm.getMemory().store(0, 4096, boot);
    }

    private static void addDisks(VirtualMachine vm, Configuration config) {
        var diskPathStrings = config.getStringArray("kronos.vm.disks");
        Arrays.stream(diskPathStrings).map(s -> Paths.get("", s).normalize()).map(Path::toAbsolutePath).forEach(path -> {
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
