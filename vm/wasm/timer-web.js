import {VirtualTimer} from "./timer.js";

export class VirtualWebTimer extends VirtualTimer {

    timerSharedBuffer
    timerFlagArray
    timerWorker

    constructor(timeout){
        super(timeout);
        this.timerSharedBuffer = new SharedArrayBuffer(1);
        this.timerFlagArray = new Uint8Array(this.timerSharedBuffer);
        this.timerWorker =new Worker(new URL('./timer-web-worker.js', import.meta.url), { type: 'module' })
        this.timerWorker.postMessage({ cmd: 'init', buffer: this.timerSharedBuffer });
    }

    start() {
        this.timerWorker.postMessage({ cmd: 'start', timeout: this.timeout });
    }

    stop() {
        this.timerWorker.postMessage({ cmd: 'stop' });
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
}
