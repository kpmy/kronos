import 'dotenv/config';
import {VirtualMachine} from "./vm.js";
import { stat } from 'fs/promises';
import {VirtualDisk} from "./disk.js";
import {VirtualConsole} from "./cons.js";

const MEMORY_SIZE = 4 * 1024 * 1024;

let addDisks = async (vm) => {
    let diskPathList = process.env.KRONOS_DISKS.split(",")
    for (let diskPath of diskPathList) {
        try {
            await stat(diskPath);
            let disk = new VirtualDisk(diskPath);
            await disk.load()
            vm.addDisk(disk);
        } catch (e) {
            console.error("disk not found", diskPath, e)
        }
    }
}

let readBooter = async (vm, diskNo) => {
    let disk = vm.getDisk(diskNo);
    let boot = await disk.read(0, 4096)
    vm.getMemory().store8n(0, 4096, boot)
}

(async () => {
    //process.stdin.setRawMode(true);
    //process.stdin.resume();
    //process.stdin.setEncoding('utf8'); //TODO
    let vm = new VirtualMachine(MEMORY_SIZE, new VirtualConsole(0xFB8, 0x0C));
    await addDisks(vm)
    if (vm.getDiskCount() > 1) {
        await readBooter(vm, 1);
    }
    await vm.runSafe();
})()
