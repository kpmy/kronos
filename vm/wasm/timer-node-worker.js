import {parentPort} from 'worker_threads'

let timerFlagArray = null;
let timerIntervalId = null;

let handleMessage = function(e) {
    const { cmd, buffer, timeout } = e.data;

    if (cmd === 'init') {
        // Получаем доступ к внешнему атомику хоста
        timerFlagArray = new Uint8Array(buffer);
    }
    else if (cmd === 'start') {
        if (timerIntervalId) return;
        // Запускаем тикер: раз в миллисекунду атомарно взводим флаг в 1
        timerIntervalId = setInterval(() => {
            if (timerFlagArray) {
                Atomics.store(timerFlagArray, 0, 1);
            }
        }, timeout);
    }
    else if (cmd === 'stop') {
        if (timerIntervalId) {
            clearInterval(timerIntervalId);
            timerIntervalId = null;
        }
        // При остановке гарантированно сбрасываем флаг в 0
        if (timerFlagArray) {
            Atomics.store(timerFlagArray, 0, 0);
        }
    }
};

parentPort.on('message', (data) => handleMessage({ data }));
