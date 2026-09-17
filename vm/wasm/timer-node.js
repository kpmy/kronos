import {VirtualTimer} from "./timer.js";
import { Worker }  from 'worker_threads';

export class VirtualNodeTimer extends VirtualTimer {

    bTimerWorker
    bTimerSharedBuffer
    bTimerFlagArray

    constructor(timeout) {
        super(timeout);
        this.bTimerSharedBuffer = new SharedArrayBuffer(1);
        this.bTimerFlagArray = new Uint8Array(this.bTimerSharedBuffer);
        this.bTimerWorker = new Worker('./timer-node-worker.js');
        this.bTimerWorker.postMessage({ cmd: 'init', buffer: this.bTimerSharedBuffer });
    }

    timer() {
        // Атомарно и очень быстро читаем состояние внешнего флага "провода"
        if (Atomics.load(this.bTimerFlagArray, 0) === 1) {
            // 1. Сбрасываем внешний флаг обратно в 0, так как прерывание поймано
            Atomics.store(this.bTimerFlagArray, 0, 0);
            //this.console._writeGuestChar('.'.charCodeAt(0))
            return true;
        } else {
            return false;
        }
    }

    start() {
        this.bTimerWorker.postMessage({ cmd: 'start', timeout: this.timeout });
    }

    stop() {
        this.bTimerWorker.postMessage({ cmd: 'stop' });
    }
}
