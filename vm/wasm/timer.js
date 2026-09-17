export class VirtualTimer {
    timeout;        // Целевой таймаут в миллисекундах (например, 100)
    counter;        // Счетчик внешних прерываний
    last;           // Время последнего успешного срабатывания или сброса
    freq;           // Текущий шаг пропуска (сколько вызовов нужно пропустить)
    smoothedMs;     // Экспоненциальное скользящее среднее времени выполнения (в мс)
    isRunning;      // Флаг активности таймера

    constructor(timeoutInMs = 100) {
        this.timeout = timeoutInMs;
        this.counter = 0;
        this.last = performance.now();
        this.freq = 64;
        // Стартовое сглаженное время инициализируем равным целевому таймауту
        this.smoothedMs = this.timeout;
        this.isRunning = false;
    }

    timer() {
        if (!this.isRunning) return false;

        this.counter++;

        let now = performance.now();
        let msSinceLastTrigger = now - this.last;

        // --- АВАРИЙНЫЙ СБРОС (ПРИ РЕЗКОМ ЗАМЕДЛЕНИИ ВНЕШНИХ ВЫЗОВОВ) ---
        // Если реальное время ожидания превысило целевой таймаут в 3 раза,
        // а счетчик из-за высокого freq всё еще не дополз до конца:
        if (msSinceLastTrigger > (this.timeout * 3) && this.freq > 4) {
            this.freq = 4;        // Мгновенно сбрасываем пропуски до минимума
            this.counter = 0;     // Обнуляем счетчик, чтобы сразу начать обработку на высокой чувствительности
            this.last = now;
            this.smoothedMs = this.timeout; // Сбрасываем историю сглаживания

            //console.log(`[Watchdog Reset] New freq: ${this.freq}`);
            return true;          // Вынужденно триггерим срабатывание
        }

        // --- СТАНДАРТНЫЙ ПЛАВНЫЙ АЛГОРИТМ ---
        if (this.counter >= this.freq) {
            // Скользящее среднее (alpha = 0.15 защищает от случайных рваных прыжков)
            const alpha = 0.15;
            this.smoothedMs = (alpha * msSinceLastTrigger) + ((1 - alpha) * this.smoothedMs);

            // Подстройка freq на основе СГЛАЖЕННОГО тренда времени
            if (this.smoothedMs < this.timeout) {
                // Стабильно идем быстрее таймаута -> плавно увеличиваем пропуски
                this.freq = Math.min(2048, this.freq + 2);
            } else if (this.smoothedMs > this.timeout) {
                // Стабильно отстаем от таймаута -> плавно уменьшаем пропуски
                this.freq = Math.max(4, this.freq - 2);
            }

            this.last = now;
            this.counter = 0;

            //console.log(`[Timer Trigger] Freq: ${this.freq}, Smoothed: ${Math.round(this.smoothedMs)}ms`);
            return true; // Срабатывание триггера таймаута
        }

        return false;
    }

    start() {
        this.isRunning = true;
        this.last = performance.now();
        this.counter = 0;
    }

    stop() {
        this.isRunning = false;
    }
}
