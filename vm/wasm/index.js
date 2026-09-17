import 'dotenv/config';
import {VirtualMachine} from "./vm.js";
import {VirtualDisk} from "./disk.js";
import {VirtualConsole} from "./cons.js";
import * as fs from "node:fs/promises";
import * as readline from "node:readline";
import {IR} from "./mem.js";
import wabt from "wabt";
import {readFile, stat} from 'fs/promises'
import * as path from "node:path";
import {VirtualConsoleCli} from "./cons-cli.js";
import {VirtualNodeTimer} from "./timer-node.js";


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

let loadTrace = async (vm) => {
    let trace = [];
    let minStep = Number.MAX_VALUE;
    if (process.env.KRONOS_TRACE) {
        try {
            await stat(process.env.KRONOS_TRACE);
            const file = await fs.open(process.env.KRONOS_TRACE, 'r');
            const rl = readline.createInterface({
                input: file.createReadStream(),
                crlfDelay: Infinity
            });
            for await (const line of rl) {
                if (line.startsWith("Step =")){
                    let lineRet = {}
                    let lineValues = line.split(", ")
                    for (let lineValue of lineValues){
                        let lv = lineValue.split(" = ")
                        if (lv[0] === "PC" || lv[0] === "IR") {
                            lineRet[lv[0]] = parseInt(lv[1], 16)
                        } else {
                            lineRet[lv[0]] = parseInt(lv[1])
                        }
                    }
                    trace.push(lineRet);
                    minStep = Math.min(lineRet['Step'], minStep);
                }
            }
            console.log(`loaded ${trace.length} traces starting from ${minStep}`);
        } catch (e) {
            throw e;
        }

        vm.trace =  trace;
        vm.traceMinStep = minStep;
        vm.traceFn = () => {
            if (vm.trace.length === 0) {
                if (!process.env.KRONOS_TRACE) {
                    return
                } else {
                    throw 'empty trace...'
                }
            }
            if(vm.stepIdx - 1 < vm.traceMinStep){
                return;
            }
            let stepTrace = vm.trace.shift()
            if (stepTrace == null) {
                return;
            }
            if (stepTrace['Step'] != vm.stepIdx - 1) {
                debugger
            }
            if (stepTrace['IR'] != vm.memory.getReg(IR)){
                debugger
            }
        }
    }
}

let loadCore = async (vm) => {
    let wabtModule = await wabt();
    const wastCode = await readFile(path.join(process.cwd(), 'core.wat'), 'utf-8')
    const parsedModule = wabtModule.parseWat('core.wat', wastCode);
    const { buffer } = parsedModule.toBinary({ log: true, canonicalize_lebs: true });
    const wasmModule = await WebAssembly.compile(buffer);
    vm.core = wasmModule
}

(async () => {
    let vm = new VirtualMachine(MEMORY_SIZE, new VirtualConsoleCli(0xFB8, 0x0C), new VirtualNodeTimer(33));
    await loadCore(vm)
    await loadTrace(vm)
    await addDisks(vm)
    if (vm.getDiskCount() > 1) {
        await vm.readBooter(1);
    }
    await vm.runSafe();
})()
