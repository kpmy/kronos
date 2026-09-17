// timer-worker.js (для браузера под Vite)
let timerFlagArray = null;
let timerIntervalId = null;

// Слушаем сообщения через глобальный self
self.onmessage = function(e) {
    const { cmd, buffer, timeout } = e.data;

    if (cmd === 'init') {
        timerFlagArray = new Uint8Array(buffer);
    }
    else if (cmd === 'start') {
        if (timerIntervalId) return;
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
        if (timerFlagArray) {
            Atomics.store(timerFlagArray, 0, 0);
        }
    }
};
