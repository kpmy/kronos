(module
  (import "env" "memory" (memory $mem 1))
  ;; НАША ОТЛАДОЧНАЯ ФУНКЦИЯ: принимает (id_точки, значение)
  (import "env" "log_debug" (func $log_debug (param i32 i32)))
  ;; Импортируем функцию обработки ввода-вывода из JavaScript-хоста с одним параметром
  (import "env" "io_host_call" (func $io_host_call (param i32)))

  ;; Абсолютные адреса регистров в WebAssembly.Memory (База + Индекс * 4)
  (global $IPT_ADDR (mut i32)
    (i32.const 0)) ;; 4  (Индекс 1) //код прерывания
  (global $SP_ADDR (mut i32)
    (i32.const 0)) ;; 8  (Индекс 2) //указатель на стек выражений (верхний элемент)
  (global $PC_ADDR (mut i32)
    (i32.const 0)) ;; 12 (Индекс 3) //указатель на инструкцию
  (global $IR_ADDR (mut i32)
    (i32.const 0)) ;; 16 (Индекс 4)  //инструкция
  (global $P_ADDR (mut i32)
    (i32.const 0)) ;; 20 (Индекс 5) //память процесса
  (global $L_ADDR (mut i32)
    (i32.const 0)) ;; 24 (Индекс 6) //область локальных данных текущей процедуры на стеке
  (global $G_ADDR (mut i32)
    (i32.const 0)) ;; 28 (Индекс 7) //область глобальных данных модуля
  (global $M_ADDR (mut i32)
    (i32.const 0)) ;; 32 (Индекс 8) //маска прерываний
  (global $H_ADDR (mut i32)
    (i32.const 0)) ;; 36 (Индекс 9) //конец процедурного стека
  (global $S_ADDR (mut i32)
    (i32.const 0)) ;; 40 (Индекс 10)  //указатель на процедурный стек (верхний элемент)
  (global $F_ADDR (mut i32)
    (i32.const 0)) ;; 44 (Индекс 11)  //указатель на начало сегмента кода текущей процедуры
  (global $CODE_ADDR (mut i32)
    (i32.const 0)) ;; 48 (Индекс 12) //указатель на инструкцию
  (global $STACK_ADDR (mut i32)
    (i32.const 0)) ;; 128 (Индекс 32) //СТЕК

  (global $ASTACK_SIZE (mut i32)
    (i32.const 0)) ;; размер стека
  (global $MEM_SIZE (mut i32)
    (i32.const 0)) ;; размер памяти

  ;; Функция PUSH: принимает значение i32
  (func $push (param $value i32)
    (local $sp i32)

    ;; 1. let sp = this.memory.getReg(SP)
    (local.set $sp
      (i32.load
        (global.get $SP_ADDR)))

    ;; 2. Проверка условий: if (sp >= 0 && sp < AStackSize)
    ;; Примечание: в вашем JS было (sp <= 0), но судя по логике (sp + 1) и (STACK + sp),
    ;; индекс должен быть неотрицательным: sp >= 0
    (if
      (i32.and
        (i32.ge_s
          (local.get $sp)
          (i32.const 0))
        (i32.lt_s
          (local.get $sp)
          (global.get $ASTACK_SIZE)) ;; Подставьте вашу константу AStackSize
      )
      ;; --- ВЕТКА IF: всё хорошо, пишем в стек ---
      (then
        ;; this.memory.setReg(i32, STACK + sp)
        ;; Вычисляем физический адрес: STACK_ADDR + (sp * 4)
        (i32.store
          (i32.add
            (global.get $STACK_ADDR)
            (i32.mul
              (local.get $sp)
              (i32.const 4)))
          (local.get $value))

        ;; this.memory.setReg(sp + 1, SP)
        (i32.store
          (global.get $SP_ADDR)
          (i32.add
            (local.get $sp)
            (i32.const 1))))
      ;; --- ВЕТКА ELSE: выход за границы стека ---
      (else
        ;; this.memory.setReg(0x4C, IPT)
        (i32.store
          (global.get $IPT_ADDR)
          (i32.const 0x4C)))))

  ;; ========================================================
  ;; Функция POP (для контроля структуры, без изменений)
  ;; ========================================================
  (func $pop (export "pop") (result i32)
    (local $sp i32)
    (local $top_val i32)

    (local.set $sp
      (i32.load
        (global.get $SP_ADDR)))

    (if
      (i32.gt_s
        (local.get $sp)
        (i32.const 0))
      (then
        (local.set $sp
          (i32.sub
            (local.get $sp)
            (i32.const 1)))
        (local.set $top_val
          (i32.load
            (i32.add
              (global.get $STACK_ADDR)
              (i32.mul
                (local.get $sp)
                (i32.const 4)))))
        (i32.store
          (global.get $SP_ADDR)
          (local.get $sp)))
      (else
        (i32.store
          (global.get $IPT_ADDR)
          (i32.const 0x4C))
        (local.set $top_val
          (i32.const 0))))
    (local.get $top_val))

  ;; Функция next: переводит CODE в байты, складывает с байтовым PC,
  ;; читает 1 байт, сдвигает PC на 1 и возвращает результат.
  (func $next (result i32)
    (local $code_words i32) ;; Значение регистра CODE в словах
    (local $code_bytes i32) ;; Значение регистра CODE, переведенное в байты
    (local $pc_offset i32) ;; Оффсет из регистра PC в байтах
    (local $phys_addr i32) ;; Итоговый физический адрес для чтения
    (local $fetched_val i32) ;; Считанный байт аргумента

    ;; 1. Читаем значение CODE (в словах) из памяти регистров
    (local.set $code_words
      (i32.load
        (global.get $CODE_ADDR)))

    ;; 2. Переводим слова в байты: CODE * 4
    (local.set $code_bytes
      (i32.mul
        (local.get $code_words)
        (i32.const 4)))

    ;; 3. Читаем текущее значение PC (в байтах)
    (local.set $pc_offset
      (i32.load
        (global.get $PC_ADDR)))

    ;; 4. Вычисляем физический адрес: (CODE * 4) + PC
    (local.set $phys_addr
      (i32.add
        (local.get $code_bytes)
        (local.get $pc_offset)))

    ;; 5. Читаем 1 байт по вычисленному адресу
    (local.set $fetched_val
      (i32.load8_u
        (local.get $phys_addr)))

    ;; 6. Увеличиваем байтовый оффсет PC на 1 и сохраняем обратно в регистр PC
    (i32.store
      (global.get $PC_ADDR)
      (i32.add
        (local.get $pc_offset)
        (i32.const 1)))

    ;; 7. Возвращаем считанный байт
    (local.get $fetched_val))

  ;; ========================================================
  ;; Вспомогательная функция NEXT4 (С сохранением логики PC)
  ;; Читает 32-битное слово по адресу (CODE * 4) + PC,
  ;; всегда сдвигает PC на 4, но при выходе за границы взводит IPT=3 и возвращает 0.
  ;; ========================================================
  (func $next4 (export "next4") (result i32)
    (local $code_words i32)
    (local $code_bytes i32)
    (local $pc_offset i32)
    (local $phys_addr i32)
    (local $max_safe_byte i32)
    (local $fetched_word i32)

    ;; 1. Рассчитываем физический адрес и оффсеты
    (local.set $code_words
      (i32.load
        (global.get $CODE_ADDR)))
    (local.set $code_bytes
      (i32.mul
        (local.get $code_words)
        (i32.const 4)))
    (local.set $pc_offset
      (i32.load
        (global.get $PC_ADDR)))
    (local.set $phys_addr
      (i32.add
        (local.get $code_bytes)
        (local.get $pc_offset)))

    ;; Вычисляем максимальный разрешенный байт для старта чтения 4-байтового слова
    (local.set $max_safe_byte
      (i32.sub
        (global.get $MEM_SIZE)
        (i32.const 4)))

    ;; 2. ВАЛИДАЦИЯ ГРАНИЦ: if (phys_addr < 0 || phys_addr > max_safe_byte)
    (if
      (i32.or
        (i32.lt_s
          (local.get $phys_addr)
          (i32.const 0))
        (i32.gt_s
          (local.get $phys_addr)
          (local.get $max_safe_byte)))
      ;; --- ВЕТКА TRUE: Выход за границы ---
      (then
        ;; ipt = 3;
        (i32.store
          (global.get $IPT_ADDR)
          (i32.const 3))
        ;; Записываем заглушку 0
        (local.set $fetched_word
          (i32.const 0)))
      ;; --- ВЕТКА FALSE: Все отлично, читаем данные нативно ---
      (else
        (local.set $fetched_word
          (i32.load
            (local.get $phys_addr)))))

    ;; 3. ВСЕГДА увеличиваем байтовый оффсет PC на 4 (независимо от успеха чтения)
    (i32.store
      (global.get $PC_ADDR)
      (i32.add
        (local.get $pc_offset)
        (i32.const 4)))

    ;; 4. Возвращаем результат
    (local.get $fetched_word))

  ;; ========================================================
  ;; Вспомогательная функция NEXT2
  ;; Читает 16-битное число по адресу (CODE * 4) + PC,
  ;; всегда сдвигает PC на 2, но при выходе за границы взводит IPT=3 и возвращает 0.
  ;; ========================================================
  (func $next2 (export "next2") (result i32)
    (local $code_words i32)
    (local $code_bytes i32)
    (local $pc_offset i32)
    (local $phys_addr i32)
    (local $max_safe_byte i32)
    (local $fetched_half i32)

    ;; 1. Рассчитываем физический адрес
    (local.set $code_words
      (i32.load
        (global.get $CODE_ADDR)))
    (local.set $code_bytes
      (i32.mul
        (local.get $code_words)
        (i32.const 4)))
    (local.set $pc_offset
      (i32.load
        (global.get $PC_ADDR)))
    (local.set $phys_addr
      (i32.add
        (local.get $code_bytes)
        (local.get $pc_offset)))

    ;; Вычисляем максимальный разрешенный байт для старта чтения 2-байтового числа
    (local.set $max_safe_byte
      (i32.sub
        (global.get $MEM_SIZE)
        (i32.const 2)))

    ;; 2. ВАЛИДАЦИЯ ГРАНИЦ: if (phys_addr < 0 || phys_addr > max_safe_byte)
    (if
      (i32.or
        (i32.lt_s
          (local.get $phys_addr)
          (i32.const 0))
        (i32.gt_s
          (local.get $phys_addr)
          (local.get $max_safe_byte)))
      ;; --- ВЕТКА TRUE: Выход за границы ---
      (then
        (i32.store
          (global.get $IPT_ADDR)
          (i32.const 3))
        (local.set $fetched_half
          (i32.const 0)))
      ;; --- ВЕТКА FALSE: Читаем 2 байта без знака ---
      (else
        (local.set $fetched_half
          (i32.load16_u
            (local.get $phys_addr)))))

    ;; 3. ВСЕГДА увеличиваем байтовый оффсет PC на 2
    (i32.store
      (global.get $PC_ADDR)
      (i32.add
        (local.get $pc_offset)
        (i32.const 2)))

    ;; 4. Возвращаем результат
    (local.get $fetched_half))

  ;; ========================================================
  ;; Вспомогательная функция MARK
  ;; @param $x       - значение для записи (i32)
  ;; @param $extern   - флаг extern (i32: 1 = true, 0 = false)
  ;; ========================================================
  (func $mark (export "mark") (param $x i32) (param $extern i32)
    (local $i i32)
    (local $s i32)
    (local $l i32)
    (local $pc i32)

    ;; Читаем текущие значения регистров S, L, PC
    (local.set $s
      (i32.load
        (global.get $S_ADDR)))
    (local.set $l
      (i32.load
        (global.get $L_ADDR)))
    (local.set $pc
      (i32.load
        (global.get $PC_ADDR)))

    ;; int i = s;
    (local.set $i
      (local.get $s))

    ;; mem(s++, x);
    (i32.store
      (i32.mul
        (local.get $s)
        (i32.const 4))
      (local.get $x))
    (local.set $s
      (i32.add
        (local.get $s)
        (i32.const 1)))

    ;; mem(s++, l);
    (i32.store
      (i32.mul
        (local.get $s)
        (i32.const 4))
      (local.get $l))
    (local.set $s
      (i32.add
        (local.get $s)
        (i32.const 1)))

    ;; if (extern)
    (if
      (local.get $extern)
      (then
        ;; mem(s, pc | (1 << 31))
        ;; Безопасно формируем маску через нативный сдвиг i32.shl
        (i32.store
          (i32.mul
            (local.get $s)
            (i32.const 4))
          (i32.or
            (local.get $pc)
            (i32.shl
              (i32.const 1)
              (i32.const 31)))))
      (else
        ;; mem(s, pc);
        (i32.store
          (i32.mul
            (local.get $s)
            (i32.const 4))
          (local.get $pc))))

    ;; s += 2; (так как мы уже дважды сделали s++, здесь прибавляем оставшиеся 2)
    (local.set $s
      (i32.add
        (local.get $s)
        (i32.const 2)))

    ;; Сохраняем обновленный регистр S обратно в память
    (i32.store
      (global.get $S_ADDR)
      (local.get $s))

    ;; l = i;
    (i32.store
      (global.get $L_ADDR)
      (local.get $i)))

  (func (export "init_vm") (param $total_pages i32) (param $stack_size i32)
    ;; Локальная переменная для хранения базового адреса начала регистров
    (local $reg_base i32)

    ;; 1. Вычисляем адрес начала регистров: (TOTAL_PAGES - 1) * 65536
    ;; Для TOTAL_PAGES = 65, это даст ровно 4194304 (начало 65-й страницы)
    (local.set $reg_base
      (i32.mul
        (i32.sub
          (local.get $total_pages)
          (i32.const 1))
        (i32.const 65536)))

    ;; 2. Инициализируем абсолютные адреса регистров (База + Смещение в байтах)
    (global.set $IPT_ADDR
      (i32.add
        (local.get $reg_base)
        (i32.const 4)))
    (global.set $SP_ADDR
      (i32.add
        (local.get $reg_base)
        (i32.const 8)))
    (global.set $PC_ADDR
      (i32.add
        (local.get $reg_base)
        (i32.const 12)))
    (global.set $IR_ADDR
      (i32.add
        (local.get $reg_base)
        (i32.const 16)))
    (global.set $P_ADDR
      (i32.add
        (local.get $reg_base)
        (i32.const 20)))
    (global.set $L_ADDR
      (i32.add
        (local.get $reg_base)
        (i32.const 24)))
    (global.set $G_ADDR
      (i32.add
        (local.get $reg_base)
        (i32.const 28)))
    (global.set $M_ADDR
      (i32.add
        (local.get $reg_base)
        (i32.const 32)))
    (global.set $H_ADDR
      (i32.add
        (local.get $reg_base)
        (i32.const 36)))
    (global.set $S_ADDR
      (i32.add
        (local.get $reg_base)
        (i32.const 40)))
    (global.set $F_ADDR
      (i32.add
        (local.get $reg_base)
        (i32.const 44)))
    (global.set $CODE_ADDR
      (i32.add
        (local.get $reg_base)
        (i32.const 48)))
    (global.set $STACK_ADDR
      (i32.add
        (local.get $reg_base)
        (i32.const 128)))

    (global.set $ASTACK_SIZE
      (local.get $stack_size))
    (global.set $MEM_SIZE
      (local.get $reg_base)))

  ;; Динамический JIT-код для конкретной инструкции LIB
  (func (export "ir_LIB")
    (call $push
      (call $next)))

  ;; Функция LSW: модифицирует верхнее значение стека, прибавляя (ir & 0xF),
  ;; проверяет границы памяти, загружает слово (или 0 при ошибке) и пишет на стек.
  (func $ir_LSW (export "ir_LSW")
    (local $ir i32)
    (local $sp_idx i32)
    (local $top_val_addr i32)
    (local $target_word_addr i32) ;; Гостевой адрес в СЛОВАХ
    (local $target_byte_addr i32) ;; Гостевой адрес в БАЙТАХ (для Wasm)
    (local $max_safe_byte i32)
    (local $loaded_word i32)

    ;; 1. Читаем инструкцию из регистра IR
    (local.set $ir
      (i32.load
        (global.get $IR_ADDR)))

    ;; 2. Находим sp - 1 (индекс верхнего элемента стека)
    (local.set $sp_idx
      (i32.sub
        (i32.load
          (global.get $SP_ADDR))
        (i32.const 1)))

    ;; 3. Вычисляем физический адрес ячейки astack[sp-1] в памяти Wasm
    (local.set $top_val_addr
      (i32.add
        (global.get $STACK_ADDR)
        (i32.mul
          (local.get $sp_idx)
          (i32.const 4))))

    ;; 4. Вычисляем гостевой адрес в СЛОВАХ: astack[sp-1] + (ir & 0xF)
    (local.set $target_word_addr
      (i32.add
        (i32.load
          (local.get $top_val_addr)) ;; Значение слова из стека
        (i32.and
          (local.get $ir)
          (i32.const 0x0F)) ;; Смещение (ir & 0xF) в словах
      ))

    ;; 5. Переводим словесный адрес гостя в байтовый для WebAssembly (Умножаем на 4)
    (local.set $target_byte_addr
      (i32.mul
        (local.get $target_word_addr)
        (i32.const 4)))

    ;; Вычисляем максимальный разрешенный байт для старта чтения 4-байтового слова
    (local.set $max_safe_byte
      (i32.sub
        (global.get $MEM_SIZE)
        (i32.const 4)))

    ;; 6. МЯГКАЯ ВАЛИДАЦИЯ ГРАНИЦ: if (target_byte_addr < 0 || target_byte_addr > max_safe_byte)
    (if
      (i32.or
        (i32.lt_s
          (local.get $target_byte_addr)
          (i32.const 0))
        (i32.gt_s
          (local.get $target_byte_addr)
          (local.get $max_safe_byte)))
      ;; --- ВЕТКА TRUE: Выход за границы ---
      (then
        ;; ipt = 3;
        (i32.store
          (global.get $IPT_ADDR)
          (i32.const 3))
        ;; Записываем заглушку 0
        (local.set $loaded_word
          (i32.const 0)))
      ;; --- ВЕТКА FALSE: Всё в порядке, читаем реальное слово ---
      (else
        (local.set $loaded_word
          (i32.load
            (local.get $target_byte_addr)))))

    ;; 7. Перезаписываем вершину стека полученным результатом (словом или нулем)
    (i32.store
      (local.get $top_val_addr)
      (local.get $loaded_word)))

  ;; ========================================================
  ;; 16 пустых экспортных оберток для вашего JS-диспетчера
  ;; ========================================================
  (func (export "ir_LSW0")
    (call $ir_LSW))
  (func (export "ir_LSW1")
    (call $ir_LSW))
  (func (export "ir_LSW2")
    (call $ir_LSW))
  (func (export "ir_LSW3")
    (call $ir_LSW))
  (func (export "ir_LSW4")
    (call $ir_LSW))
  (func (export "ir_LSW5")
    (call $ir_LSW))
  (func (export "ir_LSW6")
    (call $ir_LSW))
  (func (export "ir_LSW7")
    (call $ir_LSW))
  (func (export "ir_LSW8")
    (call $ir_LSW))
  (func (export "ir_LSW9")
    (call $ir_LSW))
  (func (export "ir_LSWA")
    (call $ir_LSW))
  (func (export "ir_LSWB")
    (call $ir_LSW))
  (func (export "ir_LSWC")
    (call $ir_LSW))
  (func (export "ir_LSWD")
    (call $ir_LSW))
  (func (export "ir_LSWE")
    (call $ir_LSW))
  (func (export "ir_LSWF")
    (call $ir_LSW))

  ;; ========================================================
  ;; Обновленная инструкция COPT (Опкод 0xB5) — Чистый вызов
  ;; ========================================================
  (func (export "ir_COPT")
    (local $val i32)

    ;; 1. Вытаскиваем верхнее значение
    (local.set $val
      (call $pop))

    ;; 2. Клади его обратно дважды (параметры размеров больше не нужны!)
    (call $push
      (local.get $val))
    (call $push
      (local.get $val)))

  ;; ========================================================
  ;; Единая внутренняя логика LI (Load Immediate)
  ;; ========================================================
  (func $ir_LI
    (local $ir i32)

    ;; 1. Читаем инструкцию, которую JS уже защелкнул в регистре IR
    (local.set $ir
      (i32.load
        (global.get $IR_ADDR)))

    ;; 2. Маскируем младшие 4 бита (ir & 0xF) и отправляем результат в push
    (call $push
      (i32.and
        (local.get $ir)
        (i32.const 0x0F))))

  ;; ========================================================
  ;; 16 пустых экспортных оберток для вашего JS-диспетчера
  ;; ========================================================
  (func (export "ir_LI0")
    (call $ir_LI))
  (func (export "ir_LI1")
    (call $ir_LI))
  (func (export "ir_LI2")
    (call $ir_LI))
  (func (export "ir_LI3")
    (call $ir_LI))
  (func (export "ir_LI4")
    (call $ir_LI))
  (func (export "ir_LI5")
    (call $ir_LI))
  (func (export "ir_LI6")
    (call $ir_LI))
  (func (export "ir_LI7")
    (call $ir_LI))
  (func (export "ir_LI8")
    (call $ir_LI))
  (func (export "ir_LI9")
    (call $ir_LI))
  (func (export "ir_LI0A")
    (call $ir_LI))
  (func (export "ir_LI0B")
    (call $ir_LI))
  (func (export "ir_LI0C")
    (call $ir_LI))
  (func (export "ir_LI0D")
    (call $ir_LI))
  (func (export "ir_LI0E")
    (call $ir_LI))
  (func (export "ir_LI0F")
    (call $ir_LI))

  ;; ========================================================
  ;; Инструкция EQU (Опкод 0xA4) — Сравнение двух верхних элементов стека
  ;; ========================================================
  (func (export "ir_EQU")
    (local $sp i32)
    (local $val2 i32) ;; Верхний элемент (astack[sp])
    (local $val1 i32) ;; Предыдущий элемент (astack[sp-1])

    ;; 1. Читаем текущее значение SP из памяти регистров
    (local.set $sp
      (i32.load
        (global.get $SP_ADDR)))

    ;; 2. Проверяем условие: if (sp <= 1)
    (if
      (i32.le_s
        (local.get $sp)
        (i32.const 1))
      (then
        ;; Записываем код ошибки в регистр прерывания
        (i32.store
          (global.get $IPT_ADDR)
          (i32.const 0x4C)))
      (else
        ;; Извлекаем верхнее значение (val2 = astack[sp])
        (local.set $val2
          (call $pop))

        ;; Извлекаем второе значение (val1 = astack[sp-1])
        (local.set $val1
          (call $pop))

        ;; Сравниваем их: val1 == val2 ? 1 : 0
        ;; Результат сравнения сразу отправляем в метод push()
        (if
          (i32.eq
            (local.get $val1)
            (local.get $val2))
          (then
            (call $push
              (i32.const 1)))
          (else
            (call $push
              (i32.const 0)))))))

  ;; ========================================================
  ;; Инструкция JFSC (Опкод 0x1A) — Точная Java-семантика
  ;; ========================================================
  (func (export "ir_JFSC")
    (local $cond i32)
    (local $pc1 i32)
    (local $current_pc i32)

    ;; 1. Вытаскиваем значение с вершины стека
    (local.set $cond
      (call $pop))

    ;; 2. Проверяем условие: if (pop() == 0)
    (if
      (i32.eqz
        (local.get $cond))
      ;; --- ВЕТКА TRUE ---
      (then
        ;; int pc1 = next(); (прочитает аргумент и сделает pc++)
        (local.set $pc1
          (call $next))

        ;; pc += pc1;
        (local.set $current_pc
          (i32.load
            (global.get $PC_ADDR)))
        (i32.store
          (global.get $PC_ADDR)
          (i32.add
            (local.get $current_pc)
            (local.get $pc1))))
      ;; --- ВЕТКА FALSE (else) ---
      (else
        ;; pc++; (просто сдвигаем PC на 1 байт вперед относительно начала инструкции)
        (local.set $current_pc
          (i32.load
            (global.get $PC_ADDR)))
        (i32.store
          (global.get $PC_ADDR)
          (i32.add
            (local.get $current_pc)
            (i32.const 1))))))

  ;; ========================================================
  ;; Инструкция STOT (Опкод 0xE8) — Сохранение на процедурный стек
  ;; ========================================================
  (func (export "ir_STOT")
    (local $s i32)
    (local $h i32)
    (local $val i32)
    (local $phys_addr i32)

    ;; 1. Читаем текущие значения регистров S и H
    (local.set $s
      (i32.load
        (global.get $S_ADDR)))
    (local.set $h
      (i32.load
        (global.get $H_ADDR)))

    ;; 2. Проверяем условие переполнения: if (s + 1 > h)
    (if
      (i32.gt_s
        (i32.add
          (local.get $s)
          (i32.const 1))
        (local.get $h))
      ;; --- ВЕТКА TRUE (Переполнение процедурного стека) ---
      (then
        ;; pc-- (возвращаем PC на начало этой инструкции)
        (i32.store
          (global.get $PC_ADDR)
          (i32.sub
            (i32.load
              (global.get $PC_ADDR))
            (i32.const 1)))
        ;; ipt = 0x40
        (i32.store
          (global.get $IPT_ADDR)
          (i32.const 0x40)))
      ;; --- ВЕТКА FALSE (Безопасная запись) ---
      (else
        ;; Извлекаем значение из стека выражений через pop()
        (local.set $val
          (call $pop))

        ;; Вычисляем физический байтовый адрес в памяти: s * 4
        (local.set $phys_addr
          (i32.mul
            (local.get $s)
            (i32.const 4)))

        ;; mem(s, pop()) -> записываем 32-битное слово в память
        (i32.store
          (local.get $phys_addr)
          (local.get $val))

        ;; s++ -> увеличиваем регистр S на 1 (слово) и сохраняем обратно
        (i32.store
          (global.get $S_ADDR)
          (i32.add
            (local.get $s)
            (i32.const 1))))))

  ;; ========================================================
  ;; Инструкция CF (Опкод 0xCE) — Вызов формальной процедуры
  ;; ========================================================
  (func (export "ir_CF")
    (local $s i32)
    (local $h i32)
    (local $i i32)
    (local $j i32)
    (local $g i32)
    (local $f i32)
    (local $pc_target i32)

    ;; 1. Читаем текущие значения S и H
    (local.set $s
      (i32.load
        (global.get $S_ADDR)))
    (local.set $h
      (i32.load
        (global.get $H_ADDR)))

    ;; 2. Проверяем переполнение процедурного стека: if (s + 3 > h)
    (if
      (i32.gt_s
        (i32.add
          (local.get $s)
          (i32.const 3))
        (local.get $h))
      (then
        ;; pc--; ipt = 0x40;
        (i32.store
          (global.get $PC_ADDR)
          (i32.sub
            (i32.load
              (global.get $PC_ADDR))
            (i32.const 1)))
        (i32.store
          (global.get $IPT_ADDR)
          (i32.const 0x40)))
      (else
        ;; s--;
        (local.set $s
          (i32.sub
            (local.get $s)
            (i32.const 1)))
        (i32.store
          (global.get $S_ADDR)
          (local.get $s))

        ;; int i = mem(s); (адресация в словах, умножаем на 4)
        (local.set $i
          (i32.load
            (i32.mul
              (local.get $s)
              (i32.const 4))))

        ;; mark(g, true); (передаем текущее значение регистра G и флаг extern = 1)
        (call $mark
          (i32.load
            (global.get $G_ADDR))
          (i32.const 1))

        ;; Извлекаем параметры из i:
        ;; int j = (i >> 24) & 0xFF;
        (local.set $j
          (i32.and
            (i32.shr_u
              (local.get $i)
              (i32.const 24))
            (i32.const 0xFF)))
        ;; i = i & 0xFFFFFF;
        (local.set $i
          (i32.and
            (local.get $i)
            (i32.const 0xFFFFFF)))

        ;; g = mem(i);
        (local.set $g
          (i32.load
            (i32.mul
              (local.get $i)
              (i32.const 4))))
        (i32.store
          (global.get $G_ADDR)
          (local.get $g))

        ;; f = mem(g);
        (local.set $f
          (i32.load
            (i32.mul
              (local.get $g)
              (i32.const 4))))
        (i32.store
          (global.get $F_ADDR)
          (local.get $f))

        ;; --- Реализация getCode(f) с проверкой границ ---
        ;; if (f < 0 || f > memory.getSize()) ipt = 3;
        (if
          (i32.or
            (i32.lt_s
              (local.get $f)
              (i32.const 0))
            (i32.gt_s
              (local.get $f)
              (global.get $MEM_SIZE)))
          (then
            (i32.store
              (global.get $IPT_ADDR)
              (i32.const 3)))
          (else
            ;; pcode = getCode(f); -> записываем f в регистр CODE
            (i32.store
              (global.get $CODE_ADDR)
              (local.get $f))))

        ;; pc = mem(f + j); (адресация в словах, умножаем сумму на 4)
        (local.set $pc_target
          (i32.load
            (i32.mul
              (i32.add
                (local.get $f)
                (local.get $j))
              (i32.const 4))))
        (i32.store
          (global.get $PC_ADDR)
          (local.get $pc_target)))))

  ;; ========================================================
  ;; Инструкция RTN (Опкод 0xCA) — Возврат из процедуры
  ;; ========================================================
  (func (export "ir_RTN")
    (local $s i32)
    (local $l i32)
    (local $i i32)
    (local $g i32)
    (local $f i32)
    (local $pc_val i32)

    ;; 1. s = l; (Устанавливаем s на начало текущего кадра локальных данных)
    (local.set $s
      (i32.load
        (global.get $L_ADDR)))
    (i32.store
      (global.get $S_ADDR)
      (local.get $s))

    ;; 2. l = mem(s + 1); (Восстанавливаем предыдущий указатель кадра)
    ;; s + 1 в словах -> (s + 1) * 4 в байтах
    (local.set $l
      (i32.load
        (i32.mul
          (i32.add
            (local.get $s)
            (i32.const 1))
          (i32.const 4))))
    (i32.store
      (global.get $L_ADDR)
      (local.get $l))

    ;; 3. int i = mem(s + 2); (Читаем упакованное значение возврата)
    (local.set $i
      (i32.load
        (i32.mul
          (i32.add
            (local.get $s)
            (i32.const 2))
          (i32.const 4))))

    ;; 4. pc = i & 0xFFFF; (Извлекаем адрес возврата)
    (local.set $pc_val
      (i32.and
        (local.get $i)
        (i32.const 0xFFFF)))
    (i32.store
      (global.get $PC_ADDR)
      (local.get $pc_val))

    ;; 5. Проверяем 31-й бит: if ((i & 0x80000000) != 0)
    ;; Формируем маску 0x80000000 через безопасный i32.shl
    (if
      (i32.and
        (local.get $i)
        (i32.shl
          (i32.const 1)
          (i32.const 31)))
      (then
        ;; g = mem(s);
        (local.set $g
          (i32.load
            (i32.mul
              (local.get $s)
              (i32.const 4))))
        (i32.store
          (global.get $G_ADDR)
          (local.get $g))

        ;; f = mem(g);
        (local.set $f
          (i32.load
            (i32.mul
              (local.get $g)
              (i32.const 4))))
        (i32.store
          (global.get $F_ADDR)
          (local.get $f))

        ;; --- Аналог getCode(f) с проверкой границ ---
        (if
          (i32.or
            (i32.lt_s
              (local.get $f)
              (i32.const 0))
            (i32.gt_s
              (local.get $f)
              (global.get $MEM_SIZE)))
          (then
            (i32.store
              (global.get $IPT_ADDR)
              (i32.const 3)))
          (else
            ;; pcode = getCode(f); -> обновляем CODE регистр
            (i32.store
              (global.get $CODE_ADDR)
              (local.get $f)))))))

  ;; ========================================================
  ;; Инструкция DROP (Опкод 0xB1) — Удаление вершины стека
  ;; ========================================================
  (func (export "ir_DROP")
    ;; Вызываем pop() и сразу сбрасываем возвращенное значение со стека WASM
    (call $pop)
    (drop))

  ;; ========================================================
  ;; Инструкция LODT (Опкод 0xE9) — Загрузка с процедурного стека
  ;; ========================================================
  (func (export "ir_LODT")
    (local $s i32)
    (local $phys_addr i32)
    (local $loaded_word i32)

    ;; 1. Читаем текущее значение регистра S
    (local.set $s
      (i32.load
        (global.get $S_ADDR)))

    ;; 2. Выполняем декремент: --s (уменьшаем на 1 слово)
    (local.set $s
      (i32.sub
        (local.get $s)
        (i32.const 1)))

    ;; 3. Сохраняем обновленный регистр S обратно в память регистров
    (i32.store
      (global.get $S_ADDR)
      (local.get $s))

    ;; 4. Переводим словесный адрес в байтовый физический адрес: s * 4
    (local.set $phys_addr
      (i32.mul
        (local.get $s)
        (i32.const 4)))

    ;; 5. Читаем 32-битное слово из памяти программы
    (local.set $loaded_word
      (i32.load
        (local.get $phys_addr)))

    ;; 6. Кладем прочитанное слово на стек выражений
    (call $push
      (local.get $loaded_word)))

  ;; ========================================================
  ;; Инструкция ADD (Опкод 0x88) — Сложение двух верхних элементов стека
  ;; ========================================================
  (func (export "ir_ADD")
    (local $sp i32)
    (local $val2 i32) ;; Верхний элемент (astack[sp])
    (local $val1 i32) ;; Предыдущий элемент (astack[sp-1])

    ;; 1. Читаем текущее значение SP из памяти регистров
    (local.set $sp
      (i32.load
        (global.get $SP_ADDR)))

    ;; 2. Проверяем условие нехватки элементов: if (sp <= 1)
    (if
      (i32.le_s
        (local.get $sp)
        (i32.const 1))
      (then
        ;; Взводим код прерывания IPT
        (i32.store
          (global.get $IPT_ADDR)
          (i32.const 0x4C)))
      (else
        ;; Извлекаем второй (самый верхний) операнд
        (local.set $val2
          (call $pop))

        ;; Извлекаем первый операнд
        (local.set $val1
          (call $pop))

        ;; Складываем их нативно в CPU и возвращаем результат на стек
        (call $push
          (i32.add
            (local.get $val1)
            (local.get $val2))))))

  ;; ========================================================
  ;; Инструкция JBS (Опкод 0x1F) — Безусловный переход назад
  ;; ========================================================
  (func (export "ir_JBS")
    (local $pc1 i32)
    (local $current_pc i32)

    ;; 1. int pc1 = next(); (считывает смещение и сдвигает PC вперед на 1 байт)
    (local.set $pc1
      (call $next))

    ;; 2. pc -= pc1; (вычитаем смещение из текущего значения регистра PC)
    (local.set $current_pc
      (i32.load
        (global.get $PC_ADDR)))
    (i32.store
      (global.get $PC_ADDR)
      (i32.sub
        (local.get $current_pc)
        (local.get $pc1))))

  ;; ========================================================
  ;; Единая внутренняя логика CL (Call Local)
  ;; ========================================================
  (func $ir_CL
    (local $s i32)
    (local $h i32)
    (local $ir i32)
    (local $f i32)
    (local $offset i32)
    (local $pc_target i32)

    ;; 1. Читаем текущие значения S и H для проверки лимитов
    (local.set $s
      (i32.load
        (global.get $S_ADDR)))
    (local.set $h
      (i32.load
        (global.get $H_ADDR)))

    ;; 2. if (s + 4 > h)
    (if
      (i32.gt_s
        (i32.add
          (local.get $s)
          (i32.const 4))
        (local.get $h))
      ;; --- ВЕТКА TRUE (Переполнение) ---
      (then
        ;; pc--; ipt = 0x40;
        (i32.store
          (global.get $PC_ADDR)
          (i32.sub
            (i32.load
              (global.get $PC_ADDR))
            (i32.const 1)))
        (i32.store
          (global.get $IPT_ADDR)
          (i32.const 0x40)))
      ;; --- ВЕТКА FALSE (Успешный вызов) ---
      (else
        ;; mark(l, false) -> передаем значение текущего регистра L и extern = 0
        (call $mark
          (i32.load
            (global.get $L_ADDR))
          (i32.const 0))

        ;; Читаем защелкнутый IR и текущий регистр F
        (local.set $ir
          (i32.load
            (global.get $IR_ADDR)))
        (local.set $f
          (i32.load
            (global.get $F_ADDR)))

        ;; Вычисляем смещение: ir & 0xF
        (local.set $offset
          (i32.and
            (local.get $ir)
            (i32.const 0x0F)))

        ;; pc = mem(f + (ir & 0xF)) -> словесный адрес, умножаем сумму на 4
        (local.set $pc_target
          (i32.load
            (i32.mul
              (i32.add
                (local.get $f)
                (local.get $offset))
              (i32.const 4))))
        (i32.store
          (global.get $PC_ADDR)
          (local.get $pc_target)))))

  ;; ========================================================
  ;; 16 пустых экспортных оберток для вашего JS-диспетчера
  ;; ========================================================
  (func (export "ir_CL0")
    (call $ir_CL))
  (func (export "ir_CL1")
    (call $ir_CL))
  (func (export "ir_CL2")
    (call $ir_CL))
  (func (export "ir_CL3")
    (call $ir_CL))
  (func (export "ir_CL4")
    (call $ir_CL))
  (func (export "ir_CL5")
    (call $ir_CL))
  (func (export "ir_CL6")
    (call $ir_CL))
  (func (export "ir_CL7")
    (call $ir_CL))
  (func (export "ir_CL8")
    (call $ir_CL))
  (func (export "ir_CL9")
    (call $ir_CL))
  (func (export "ir_CLA")
    (call $ir_CL))
  (func (export "ir_CLB")
    (call $ir_CL))
  (func (export "ir_CLC")
    (call $ir_CL))
  (func (export "ir_CLD")
    (call $ir_CL))
  (func (export "ir_CLE")
    (call $ir_CL))
  (func (export "ir_CLF")
    (call $ir_CL))

  ;; ========================================================
  ;; Инструкция ENTR (Опкод 0xC9) — Вход в процедуру (выделение кадра)
  ;; ========================================================
  (func (export "ir_ENTR")
    (local $sz i32)
    (local $s i32)
    (local $h i32)

    ;; 1. int sz = next(); (Считываем размер кадра и сдвигаем PC вперед на 1 байт)
    (local.set $sz
      (call $next))

    ;; 2. Читаем текущие значения S и H
    (local.set $s
      (i32.load
        (global.get $S_ADDR)))
    (local.set $h
      (i32.load
        (global.get $H_ADDR)))

    ;; 3. Проверяем переполнение: if (s + sz > h)
    (if
      (i32.gt_s
        (i32.add
          (local.get $s)
          (local.get $sz))
        (local.get $h))
      ;; --- ВЕТКА TRUE (Переполнение процедурного стека) ---
      (then
        ;; pc -= 2; (Возвращаем PC на начало инструкции ENTR)
        (i32.store
          (global.get $PC_ADDR)
          (i32.sub
            (i32.load
              (global.get $PC_ADDR))
            (i32.const 2)))
        ;; ipt = 0x40;
        (i32.store
          (global.get $IPT_ADDR)
          (i32.const 0x40)))
      ;; --- ВЕТКА FALSE (Успешное выделение памяти) ---
      (else
        ;; s += sz; (Сдвигаем вершину процедурного стека вперед на sz слов)
        (i32.store
          (global.get $S_ADDR)
          (i32.add
            (local.get $s)
            (local.get $sz))))))

  ;; ========================================================
  ;; Инструкция ALLOC (Опкод 0xC8) — Динамическое выделение блока
  ;; ========================================================
  (func (export "ir_ALLOC")
    (local $sz i32)
    (local $s i32)
    (local $h i32)

    ;; 1. int sz = pop(); (Забираем размер блока со стека выражений)
    (local.set $sz
      (call $pop))

    ;; 2. Читаем текущие значения S и H
    (local.set $s
      (i32.load
        (global.get $S_ADDR)))
    (local.set $h
      (i32.load
        (global.get $H_ADDR)))

    ;; 3. Проверяем переполнение: if (s + sz > h)
    (if
      (i32.gt_s
        (i32.add
          (local.get $s)
          (local.get $sz))
        (local.get $h))
      ;; --- ВЕТКА TRUE (Переполнение) ---
      (then
        ;; push(sz); (Возвращаем размер обратно на стек выражений)
        (call $push
          (local.get $sz))

        ;; pc--; (Откатываемся на саму инструкцию ALLOC)
        (i32.store
          (global.get $PC_ADDR)
          (i32.sub
            (i32.load
              (global.get $PC_ADDR))
            (i32.const 1)))

        ;; ipt = 0x40;
        (i32.store
          (global.get $IPT_ADDR)
          (i32.const 0x40)))
      ;; --- ВЕТКА FALSE (Успешное выделение) ---
      (else
        ;; push(s); (Кладем старый указатель вершины на стек выражений)
        (call $push
          (local.get $s))

        ;; s += sz; (Выделяем sz слов на процедурном стеке)
        (i32.store
          (global.get $S_ADDR)
          (i32.add
            (local.get $s)
            (local.get $sz))))))

  ;; ========================================================
  ;; Единая внутренняя логика SLW (Store Local Word)
  ;; ========================================================
  (func $ir_SLW
    (local $ir i32)
    (local $l i32)
    (local $val i32)
    (local $offset i32)
    (local $target_byte_addr i32)

    ;; 1. Читаем текущую инструкцию из регистра IR
    (local.set $ir
      (i32.load
        (global.get $IR_ADDR)))

    ;; 2. Забираем значение со стека выражений через pop()
    (local.set $val
      (call $pop))

    ;; 3. Читаем текущий указатель локальной области L
    (local.set $l
      (i32.load
        (global.get $L_ADDR)))

    ;; 4. Вычисляем смещение: ir & 0xF
    (local.set $offset
      (i32.and
        (local.get $ir)
        (i32.const 0x0F)))

    ;; 5. Вычисляем адрес в байтах для WebAssembly: (l + offset) * 4
    (local.set $target_byte_addr
      (i32.mul
        (i32.add
          (local.get $l)
          (local.get $offset))
        (i32.const 4)))

    ;; 6. Записываем 32-битное слово по вычисленному физическому адресу
    (i32.store
      (local.get $target_byte_addr)
      (local.get $val)))

  ;; ========================================================
  ;; 12 экспортных оберток для вашего JS-диспетчера (SLW4..SLWF)
  ;; ========================================================
  (func (export "ir_SLW4")
    (call $ir_SLW))
  (func (export "ir_SLW5")
    (call $ir_SLW))
  (func (export "ir_SLW6")
    (call $ir_SLW))
  (func (export "ir_SLW7")
    (call $ir_SLW))
  (func (export "ir_SLW8")
    (call $ir_SLW))
  (func (export "ir_SLW9")
    (call $ir_SLW))
  (func (export "ir_SLW0A")
    (call $ir_SLW))
  (func (export "ir_SLW0B")
    (call $ir_SLW))
  (func (export "ir_SLW0C")
    (call $ir_SLW))
  (func (export "ir_SLW0D")
    (call $ir_SLW))
  (func (export "ir_SLW0E")
    (call $ir_SLW))
  (func (export "ir_SLW0F")
    (call $ir_SLW))

  ;; ========================================================
  ;; Инструкция LIW (Опкод 0x12) — Теперь через вызов $next4
  ;; ========================================================
  (func (export "ir_LIW")
    ;; Вызываем next4(), результат автоматически падает на стек WASM
    ;; и сразу передается в функцию push()
    (call $push
      (call $next4)))

  ;; ========================================================
  ;; Единая внутренняя логика LLW (Load Local Word)
  ;; ========================================================
  (func $ir_LLW
    (local $ir i32)
    (local $l i32)
    (local $offset i32)
    (local $target_byte_addr i32)
    (local $loaded_word i32)

    ;; 1. Читаем текущую инструкцию из регистра IR
    (local.set $ir
      (i32.load
        (global.get $IR_ADDR)))

    ;; 2. Читаем текущий указатель локальной области L
    (local.set $l
      (i32.load
        (global.get $L_ADDR)))

    ;; 3. Вычисляем смещение из младших 4 бит опкода: ir & 0xF
    (local.set $offset
      (i32.and
        (local.get $ir)
        (i32.const 0x0F)))

    ;; 4. Вычисляем гостевой адрес в байтах для Wasm: (l + offset) * 4
    (local.set $target_byte_addr
      (i32.mul
        (i32.add
          (local.get $l)
          (local.get $offset))
        (i32.const 4)))

    ;; 5. Загружаем 32-битное слово по вычисленному адресу
    (local.set $loaded_word
      (i32.load
        (local.get $target_byte_addr)))

    ;; 6. Кладем прочитанное слово на стек выражений
    (call $push
      (local.get $loaded_word)))

  ;; ========================================================
  ;; 12 экспортных оберток для вашего JS-диспетчера (LLW4..LLWF)
  ;; ========================================================
  (func (export "ir_LLW4")
    (call $ir_LLW))
  (func (export "ir_LLW5")
    (call $ir_LLW))
  (func (export "ir_LLW6")
    (call $ir_LLW))
  (func (export "ir_LLW7")
    (call $ir_LLW))
  (func (export "ir_LLW8")
    (call $ir_LLW))
  (func (export "ir_LLW9")
    (call $ir_LLW))
  (func (export "ir_LLW0A")
    (call $ir_LLW))
  (func (export "ir_LLW0B")
    (call $ir_LLW))
  (func (export "ir_LLW0C")
    (call $ir_LLW))
  (func (export "ir_LLW0D")
    (call $ir_LLW))
  (func (export "ir_LLW0E")
    (call $ir_LLW))
  (func (export "ir_LLW0F")
    (call $ir_LLW))

  ;; ========================================================
  ;; Инструкция SUB (Опкод 0x89) — Вычитание двух верхних элементов стека
  ;; ========================================================
  (func (export "ir_SUB")
    (local $sp i32)
    (local $val2 i32) ;; Верхний операнд (astack[sp]), извлекается первым
    (local $val1 i32) ;; Нижний операнд (astack[sp-1]), извлекается вторым

    ;; 1. Читаем текущее значение SP из памяти регистров
    (local.set $sp
      (i32.load
        (global.get $SP_ADDR)))

    ;; 2. Проверяем условие нехватки элементов: if (sp <= 1)
    (if
      (i32.le_s
        (local.get $sp)
        (i32.const 1))
      (then
        ;; Взводим код прерывания IPT
        (i32.store
          (global.get $IPT_ADDR)
          (i32.const 0x4C)))
      (else
        ;; Извлекаем второй (самый верхний) операнд: astack[sp]
        (local.set $val2
          (call $pop))

        ;; Извлекаем первый операнд: astack[sp-1]
        (local.set $val1
          (call $pop))

        ;; Нативно вычитаем: val1 - val2 и отправляем разность на стек
        (call $push
          (i32.sub
            (local.get $val1)
            (local.get $val2))))))

  ;; ========================================================
  ;; Инструкция MOVE (Опкод 0xC0) — Копирование блока слов (MEM_SIZE в байтах)
  ;; ========================================================
  (func (export "ir_MOVE")
    (local $sz i32)
    (local $j i32) ;; Источник (в словах)
    (local $i i32) ;; Назначение (в словах)
    (local $j_bytes i32) ;; Источник (в байтах)
    (local $i_bytes i32) ;; Назначение (в байтах)
    (local $max_safe_byte i32)
    (local $word_val i32)

    ;; 1. Извлекаем параметры со стека выражений в строгом порядке Java
    (local.set $sz
      (call $pop))
    (local.set $j
      (i32.and
        (call $pop)
        (i32.const 0x3FFFFFFF)))
    (local.set $i
      (i32.and
        (call $pop)
        (i32.const 0x3FFFFFFF)))

    ;; Вычисляем максимальный безопасный байтовый адрес для старта чтения 4-байтового слова
    (local.set $max_safe_byte
      (i32.sub
        (global.get $MEM_SIZE)
        (i32.const 4)))

    ;; 2. Проверяем условие некорректного размера: if (sz < 0)
    (if
      (i32.lt_s
        (local.get $sz)
        (i32.const 0))
      (then
        (i32.store
          (global.get $IPT_ADDR)
          (i32.const 0x4A)))
      (else
        ;; 3. Главный цикл копирования блоков: while (sz > 0 && ipt != 3)
        (block $exit_move_loop
          (loop $move_loop
            ;; Проверяем условия продолжения цикла: sz == 0?
            (br_if $exit_move_loop
              (i32.eqz
                (local.get $sz)))

            ;; Проверяем, не взвелось ли прерывание IPT == 3
            (br_if $exit_move_loop
              (i32.eq
                (i32.load
                  (global.get $IPT_ADDR))
                (i32.const 3)))

            ;; Переводим текущие словесные указатели в байты
            (local.set $j_bytes
              (i32.mul
                (local.get $j)
                (i32.const 4)))
            (local.set $i_bytes
              (i32.mul
                (local.get $i)
                (i32.const 4)))

            ;; --- Проверка OutOfRange для байтовых адресов ---
            (if
              (i32.or
                (i32.or
                  (i32.lt_s
                    (local.get $i_bytes)
                    (i32.const 0))
                  (i32.gt_s
                    (local.get $i_bytes)
                    (local.get $max_safe_byte)))
                (i32.or
                  (i32.lt_s
                    (local.get $j_bytes)
                    (i32.const 0))
                  (i32.gt_s
                    (local.get $j_bytes)
                    (local.get $max_safe_byte))))
              (then
                (i32.store
                  (global.get $IPT_ADDR)
                  (i32.const 3))
                (br $exit_move_loop) ;; Прерываем выполнение цикла
              ))

            ;; --- Само копирование: mem(i++, mem(j++)) ---
            (local.set $word_val
              (i32.load
                (local.get $j_bytes)))
            (i32.store
              (local.get $i_bytes)
              (local.get $word_val))

            ;; Инкрементируем гостевые словесные индексы: i++, j++
            (local.set $i
              (i32.add
                (local.get $i)
                (i32.const 1)))
            (local.set $j
              (i32.add
                (local.get $j)
                (i32.const 1)))

            ;; Уменьшаем размер оставшегося блока: sz--
            (local.set $sz
              (i32.sub
                (local.get $sz)
                (i32.const 1)))

            ;; Переходим на следующую итерацию цикла
            (br $move_loop))))))

  ;; ========================================================
  ;; Единая внутренняя логика SSW (Store Stack Word)
  ;; ========================================================
  (func $ir_SSW
    (local $ir i32)
    (local $value_to_store i32) ;; Значение, извлеченное первым (i)
    (local $base_word_addr i32) ;; Базовый адрес в словах, извлеченный вторым
    (local $offset i32) ;; Смещение из инструкции (ir & 0xF)
    (local $target_byte_addr i32) ;; Итоговый физический байтовый адрес
    (local $max_safe_byte i32)

    ;; 1. Читаем текущую инструкцию из регистра IR
    (local.set $ir
      (i32.load
        (global.get $IR_ADDR)))

    ;; 2. Извлекаем первое значение со стека выражений (то, ЧТО сохраняем)
    (local.set $value_to_store
      (call $pop))

    ;; 3. Извлекаем второе значение со стека выражений (то, КУДА сохраняем - база в словах)
    (local.set $base_word_addr
      (call $pop))

    ;; 4. Вычисляем смещение из младших 4 бит опкода: ir & 0xF
    (local.set $offset
      (i32.and
        (local.get $ir)
        (i32.const 0x0F)))

    ;; 5. Вычисляем итоговый адрес в байтах для WebAssembly: (база + offset) * 4
    (local.set $target_byte_addr
      (i32.mul
        (i32.add
          (local.get $base_word_addr)
          (local.get $offset))
        (i32.const 4)))

    ;; Вычисляем максимальный разрешенный байт для старта записи 4-байтового слова
    (local.set $max_safe_byte
      (i32.sub
        (global.get $MEM_SIZE)
        (i32.const 4)))

    ;; 6. МЯГКАЯ ВАЛИДАЦИЯ ГРАНИЦ: if (target_byte_addr < 0 || target_byte_addr > max_safe_byte)
    (if
      (i32.or
        (i32.lt_s
          (local.get $target_byte_addr)
          (i32.const 0))
        (i32.gt_s
          (local.get $target_byte_addr)
          (local.get $max_safe_byte)))
      ;; --- ВЕТКА TRUE: Выход за границы ---
      (then
        ;; ipt = 3; (Просто взводим прерывание, запись игнорируем)
        (i32.store
          (global.get $IPT_ADDR)
          (i32.const 3)))
      ;; --- ВЕТКА FALSE: Всё в порядке, безопасно пишем слово ---
      (else
        (i32.store
          (local.get $target_byte_addr)
          (local.get $value_to_store)))))

  ;; ========================================================
  ;; 16 экспортных оберток для вашего JS-диспетчера (SSW0..SSWF)
  ;; ========================================================
  (func (export "ir_SSW0")
    (call $ir_SSW))
  (func (export "ir_SSW1")
    (call $ir_SSW))
  (func (export "ir_SSW2")
    (call $ir_SSW))
  (func (export "ir_SSW3")
    (call $ir_SSW))
  (func (export "ir_SSW4")
    (call $ir_SSW))
  (func (export "ir_SSW5")
    (call $ir_SSW))
  (func (export "ir_SSW6")
    (call $ir_SSW))
  (func (export "ir_SSW7")
    (call $ir_SSW))
  (func (export "ir_SSW8")
    (call $ir_SSW))
  (func (export "ir_SSW9")
    (call $ir_SSW))
  (func (export "ir_SSW0A")
    (call $ir_SSW))
  (func (export "ir_SSW0B")
    (call $ir_SSW))
  (func (export "ir_SSW0C")
    (call $ir_SSW))
  (func (export "ir_SSW0D")
    (call $ir_SSW))
  (func (export "ir_SSW0E")
    (call $ir_SSW))
  (func (export "ir_SSW0F")
    (call $ir_SSW))

  ;; ========================================================
  ;; Инструкция NEQ (Опкод 0xA5) — Сравнение на неравенство
  ;; ========================================================
  (func (export "ir_NEQ")
    (local $sp i32)
    (local $val2 i32) ;; Верхний элемент (astack[sp])
    (local $val1 i32) ;; Предыдущий element (astack[sp-1])

    ;; 1. Читаем текущее значение SP из памяти регистров
    (local.set $sp
      (i32.load
        (global.get $SP_ADDR)))

    ;; 2. Проверяем условие нехватки элементов: if (sp <= 1)
    (if
      (i32.le_s
        (local.get $sp)
        (i32.const 1))
      (then
        ;; Взводим код прерывания IPT
        (i32.store
          (global.get $IPT_ADDR)
          (i32.const 0x4C)))
      (else
        ;; Извлекаем верхнее значение (val2)
        (local.set $val2
          (call $pop))

        ;; Извлекаем предыдущее значение (val1)
        (local.set $val1
          (call $pop))

        ;; Сравниваем их на неравенство: val1 != val2 ? 1 : 0
        ;; Инструкция i32.ne нативно возвращает 1 или 0 в процессоре хоста
        (if
          (i32.ne
            (local.get $val1)
            (local.get $val2))
          (then
            (call $push
              (i32.const 1)))
          (else
            (call $push
              (i32.const 0)))))))

  ;; ========================================================
  ;; Инструкция NOT (Опкод 0xAE) — Логическое отрицание (не побитовое)
  ;; ========================================================
  (func (export "ir_NOT")
    ;; Извлекаем значение через pop(), проверяем на равенство нулю (i32.eqz)
    ;; и сразу отправляем результат обратно на стек выражений через push()
    (call $push
      (i32.eqz
        (call $pop))))

  ;; ========================================================
  ;; Единая внутренняя логика SGW (Store Global Word)
  ;; ========================================================
  (func $ir_SGW
    (local $ir i32)
    (local $g i32)
    (local $val i32)
    (local $offset i32)
    (local $target_byte_addr i32)
    (local $max_safe_byte i32)

    ;; 1. Читаем текущую инструкцию из регистра IR
    (local.set $ir
      (i32.load
        (global.get $IR_ADDR)))

    ;; 2. Забираем значение со стека выражений через pop()
    (local.set $val
      (call $pop))

    ;; 3. Читаем текущий указатель глобальной области G
    (local.set $g
      (i32.load
        (global.get $G_ADDR)))

    ;; 4. Вычисляем смещение: ir & 0xF
    (local.set $offset
      (i32.and
        (local.get $ir)
        (i32.const 0x0F)))

    ;; 5. Вычисляем адрес в байтах для WebAssembly: (g + offset) * 4
    (local.set $target_byte_addr
      (i32.mul
        (i32.add
          (local.get $g)
          (local.get $offset))
        (i32.const 4)))

    ;; Вычисляем максимальный разрешенный байт для старта записи 4-байтового слова
    (local.set $max_safe_byte
      (i32.sub
        (global.get $MEM_SIZE)
        (i32.const 4)))

    ;; 6. МЯГКАЯ ВАЛИДАЦИЯ ГРАНИЦ
    (if
      (i32.or
        (i32.lt_s
          (local.get $target_byte_addr)
          (i32.const 0))
        (i32.gt_s
          (local.get $target_byte_addr)
          (local.get $max_safe_byte)))
      ;; --- ВЕТКА TRUE: Выход за границы ---
      (then
        (i32.store
          (global.get $IPT_ADDR)
          (i32.const 3)))
      ;; --- ВЕТКА FALSE: Безопасно пишем слово ---
      (else
        (i32.store
          (local.get $target_byte_addr)
          (local.get $val)))))

  ;; ========================================================
  ;; 14 экспортных оберток для вашего JS-диспетчера (SGW2..SGWF)
  ;; ========================================================
  (func (export "ir_SGW2")
    (call $ir_SGW))
  (func (export "ir_SGW3")
    (call $ir_SGW))
  (func (export "ir_SGW4")
    (call $ir_SGW))
  (func (export "ir_SGW5")
    (call $ir_SGW))
  (func (export "ir_SGW6")
    (call $ir_SGW))
  (func (export "ir_SGW7")
    (call $ir_SGW))
  (func (export "ir_SGW8")
    (call $ir_SGW))
  (func (export "ir_SGW9")
    (call $ir_SGW))
  (func (export "ir_SGW0A")
    (call $ir_SGW))
  (func (export "ir_SGW0B")
    (call $ir_SGW))
  (func (export "ir_SGW0C")
    (call $ir_SGW))
  (func (export "ir_SGW0D")
    (call $ir_SGW))
  (func (export "ir_SGW0E")
    (call $ir_SGW))
  (func (export "ir_SGW0F")
    (call $ir_SGW))

  ;; ========================================================
  ;; Инструкция LIN (Опкод 0x13) — Загрузка Nil на стек
  ;; ========================================================
  (func (export "ir_LIN")
    ;; Константа 0x7FFFFF80 автоматически укладывается в диапазон i32
    (call $push
      (i32.const 0x7FFFFF80)))

  ;; ========================================================
  ;; Внутренняя логика обработки Ввода-Вывода (I/O)
  ;; ========================================================
  (func $io_internal
    (local $ir i32)
    (local $port i32)

    ;; 1. Читаем текущую инструкцию из регистра IR
    (local.set $ir
      (i32.load
        (global.get $IR_ADDR)))

    ;; 2. Вычисляем номер порта (no): ir & 0xF
    (local.set $port
      (i32.and
        (local.get $ir)
        (i32.const 0x0F)))

    ;; 3. Делаем вызов внешней функции Node.js с одним параметром
    (call $io_host_call
      (local.get $port)))

  ;; ========================================================
  ;; 5 экспортных оберток для вашего JS-диспетчера (IO0..IO4)
  ;; ========================================================
  (func (export "ir_IO0")
    (call $io_internal))
  (func (export "ir_IO1")
    (call $io_internal))
  (func (export "ir_IO2")
    (call $io_internal))
  (func (export "ir_IO3")
    (call $io_internal))
  (func (export "ir_IO4")
    (call $io_internal))

  ;; ========================================================
  ;; Единая внутренняя логика LGW (Load Global Word)
  ;; ========================================================
  (func $ir_LGW
    (local $ir i32)
    (local $g i32)
    (local $offset i32)
    (local $target_byte_addr i32)
    (local $max_safe_byte i32)
    (local $loaded_word i32)

    ;; 1. Читаем текущую инструкцию из регистра IR
    (local.set $ir
      (i32.load
        (global.get $IR_ADDR)))

    ;; 2. Читаем текущий указатель глобальной области G
    (local.set $g
      (i32.load
        (global.get $G_ADDR)))

    ;; 3. Вычисляем смещение: ir & 0xF
    (local.set $offset
      (i32.and
        (local.get $ir)
        (i32.const 0x0F)))

    ;; 4. Вычисляем гостевой адрес в байтах для WebAssembly: (g + offset) * 4
    (local.set $target_byte_addr
      (i32.mul
        (i32.add
          (local.get $g)
          (local.get $offset))
        (i32.const 4)))

    ;; Вычисляем максимальный разрешенный байт для старта чтения 4-байтового слова
    (local.set $max_safe_byte
      (i32.sub
        (global.get $MEM_SIZE)
        (i32.const 4)))

    ;; 5. МЯГКАЯ ВАЛИДАЦИЯ ГРАНИЦ
    (if
      (i32.or
        (i32.lt_s
          (local.get $target_byte_addr)
          (i32.const 0))
        (i32.gt_s
          (local.get $target_byte_addr)
          (local.get $max_safe_byte)))
      ;; --- ВЕТКА TRUE: Выход за границы ---
      (then
        ;; Взводим код прерывания и возвращаем 0
        (i32.store
          (global.get $IPT_ADDR)
          (i32.const 3))
        (local.set $loaded_word
          (i32.const 0)))
      ;; --- ВЕТКА FALSE: Безопасно читаем слово ---
      (else
        (local.set $loaded_word
          (i32.load
            (local.get $target_byte_addr)))))

    ;; 6. Кладем полученное слово (или 0) на стек выражений
    (call $push
      (local.get $loaded_word)))

  ;; ========================================================
  ;; 14 экспортных оберток для вашего JS-диспетчера (LGW2..LGWF)
  ;; ========================================================
  (func (export "ir_LGW2")
    (call $ir_LGW))
  (func (export "ir_LGW3")
    (call $ir_LGW))
  (func (export "ir_LGW4")
    (call $ir_LGW))
  (func (export "ir_LGW5")
    (call $ir_LGW))
  (func (export "ir_LGW6")
    (call $ir_LGW))
  (func (export "ir_LGW7")
    (call $ir_LGW))
  (func (export "ir_LGW8")
    (call $ir_LGW))
  (func (export "ir_LGW9")
    (call $ir_LGW))
  (func (export "ir_LGW0A")
    (call $ir_LGW))
  (func (export "ir_LGW0B")
    (call $ir_LGW))
  (func (export "ir_LGW0C")
    (call $ir_LGW))
  (func (export "ir_LGW0D")
    (call $ir_LGW))
  (func (export "ir_LGW0E")
    (call $ir_LGW))
  (func (export "ir_LGW0F")
    (call $ir_LGW))

  ;; ========================================================
  ;; Инструкция LSTA (Опкод 0xC2) — Загрузка адреса строки
  ;; ========================================================
  (func (export "ir_LSTA")
    (local $g i32)
    (local $g_plus_1_bytes i32)
    (local $max_safe_byte i32)
    (local $base_str_addr i32)
    (local $offset_pc2 i32)

    ;; 1. Читаем текущий регистр G
    (local.set $g
      (i32.load
        (global.get $G_ADDR)))

    ;; 2. Вычисляем физический адрес для mem(g + 1) -> (g + 1) * 4
    (local.set $g_plus_1_bytes
      (i32.mul
        (i32.add
          (local.get $g)
          (i32.const 1))
        (i32.const 4)))

    (local.set $max_safe_byte
      (i32.sub
        (global.get $MEM_SIZE)
        (i32.const 4)))

    ;; 3. Мягкая проверка для чтения базы строк mem(g + 1)
    (if
      (i32.or
        (i32.lt_s
          (local.get $g_plus_1_bytes)
          (i32.const 0))
        (i32.gt_s
          (local.get $g_plus_1_bytes)
          (local.get $max_safe_byte)))
      (then
        (i32.store
          (global.get $IPT_ADDR)
          (i32.const 3))
        (local.set $base_str_addr
          (i32.const 0)))
      (else
        (local.set $base_str_addr
          (i32.load
            (local.get $g_plus_1_bytes)))))

    ;; 4. Получаем 16-битное смещение через наш новый next2()
    (local.set $offset_pc2
      (call $next2))

    ;; 5. Складываем базу строк и смещение, результат отправляем в push()
    (call $push
      (i32.add
        (local.get $base_str_addr)
        (local.get $offset_pc2))))

  ;; ========================================================
  ;; Инструкция LXB (Опкод 0x40) — Чтение 1 байта по С-указателю
  ;; ========================================================
  (func (export "ir_LXB")
    (local $i i32) ;; Байтовое смещение, извлекается первым
    (local $j i32) ;; Базовый адрес в словах, извлекается вторым
    (local $target_byte_addr i32)
    (local $max_safe_byte i32)
    (local $loaded_byte i32)

    ;; 1. Извлекаем параметры со стека выражений в строгом порядке Java
    (local.set $i
      (call $pop))
    (local.set $j
      (call $pop))

    ;; 2. Вычисляем итоговый физический байтовый адрес: (j * 4) + i
    (local.set $target_byte_addr
      (i32.add
        (i32.mul
          (local.get $j)
          (i32.const 4))
        (local.get $i)))

    ;; Максимальный разрешенный байт для чтения 1 байта
    (local.set $max_safe_byte
      (i32.sub
        (global.get $MEM_SIZE)
        (i32.const 1)))

    ;; 3. МЯГКАЯ ВАЛИДАЦИЯ ГРАНИЦ
    (if
      (i32.or
        (i32.lt_s
          (local.get $target_byte_addr)
          (i32.const 0))
        (i32.gt_s
          (local.get $target_byte_addr)
          (local.get $max_safe_byte)))
      ;; --- ВЕТКА TRUE: Выход за границы ---
      (then
        (i32.store
          (global.get $IPT_ADDR)
          (i32.const 3))
        (local.set $loaded_byte
          (i32.const 0)))
      ;; --- ВЕТКА FALSE: Безопасно читаем 1 байт из RAM ---
      (else
        (local.set $loaded_byte
          (i32.load8_u
            (local.get $target_byte_addr)))))

    ;; 4. Кладем считанный байт на стек выражений
    (call $push
      (local.get $loaded_byte)))

  ;; ========================================================
  ;; Инструкция LSS (Опкод 0xA0) — Меньше (<)
  ;; ========================================================
  (func (export "ir_LSS")
    (local $sp i32) (local $val2 i32) (local $val1 i32)
    (local.set $sp
      (i32.load
        (global.get $SP_ADDR)))
    (if
      (i32.le_s
        (local.get $sp)
        (i32.const 1))
      (then
        (i32.store
          (global.get $IPT_ADDR)
          (i32.const 0x4C)))
      (else
        (local.set $val2
          (call $pop))
        (local.set $val1
          (call $pop))
        (if
          (i32.lt_s
            (local.get $val1)
            (local.get $val2))
          (then
            (call $push
              (i32.const 1)))
          (else
            (call $push
              (i32.const 0)))))))

  ;; ========================================================
  ;; Инструкция LEQ (Опкод 0xA1) — Меньше или равно (<=)
  ;; ========================================================
  (func (export "ir_LEQ")
    (local $sp i32) (local $val2 i32) (local $val1 i32)
    (local.set $sp
      (i32.load
        (global.get $SP_ADDR)))
    (if
      (i32.le_s
        (local.get $sp)
        (i32.const 1))
      (then
        (i32.store
          (global.get $IPT_ADDR)
          (i32.const 0x4C)))
      (else
        (local.set $val2
          (call $pop))
        (local.set $val1
          (call $pop))
        (if
          (i32.le_s
            (local.get $val1)
            (local.get $val2))
          (then
            (call $push
              (i32.const 1)))
          (else
            (call $push
              (i32.const 0)))))))

  ;; ========================================================
  ;; Инструкция GTR (Опкод 0xA2) — Больше (>)
  ;; ========================================================
  (func (export "ir_GTR")
    (local $sp i32) (local $val2 i32) (local $val1 i32)
    (local.set $sp
      (i32.load
        (global.get $SP_ADDR)))
    (if
      (i32.le_s
        (local.get $sp)
        (i32.const 1))
      (then
        (i32.store
          (global.get $IPT_ADDR)
          (i32.const 0x4C)))
      (else
        (local.set $val2
          (call $pop))
        (local.set $val1
          (call $pop))
        (if
          (i32.gt_s
            (local.get $val1)
            (local.get $val2))
          (then
            (call $push
              (i32.const 1)))
          (else
            (call $push
              (i32.const 0)))))))

  ;; ========================================================
  ;; Инструкция GEQ (Опкод 0xA3) — Больше или равно (>=)
  ;; ========================================================
  (func (export "ir_GEQ")
    (local $sp i32) (local $val2 i32) (local $val1 i32)
    (local.set $sp
      (i32.load
        (global.get $SP_ADDR)))
    (if
      (i32.le_s
        (local.get $sp)
        (i32.const 1))
      (then
        (i32.store
          (global.get $IPT_ADDR)
          (i32.const 0x4C)))
      (else
        (local.set $val2
          (call $pop))
        (local.set $val1
          (call $pop))
        (if
          (i32.ge_s
            (local.get $val1)
            (local.get $val2))
          (then
            (call $push
              (i32.const 1)))
          (else
            (call $push
              (i32.const 0)))))))

  ;; ========================================================
  ;; Инструкция LID (Опкод 0x11) — Загрузка 16-битной константы из кода
  ;; ========================================================
  (func (export "ir_LID")
    ;; Вызываем next2(), результат падает на стек WebAssembly
    ;; и сразу передается в качестве аргумента в функцию push()
    (call $push
      (call $next2)))

  ;; ========================================================
  ;; Инструкция IN (Опкод 0xAC) — Проверка вхождения в битовое множество
  ;; ========================================================
  (func (export "ir_IN")
    (local $i i32) ;; Множество битов, извлекается первым
    (local $j i32) ;; Номер бита для проверки, извлекается вторым
    (local $bit_mask i32)

    ;; 1. Извлекаем параметры со стека выражений в строгом порядке Java
    (local.set $i
      (call $pop))
    (local.set $j
      (call $pop))

    ;; 2. Проверяем границы бита: if (j >= 0 && j < 32)
    ;; В беззнаковом виде lt_u проверяет диапазон от 0 до 31 включительно
    (if
      (i32.lt_u
        (local.get $j)
        (i32.const 32))
      ;; --- ВЕТКА TRUE: бит в пределах 0..31 ---
      (then
        ;; Формируем маску нативно: 1 << j
        (local.set $bit_mask
          (i32.shl
            (i32.const 1)
            (local.get $j)))

        ;; Проверяем: ((1 << j) & i) != 0 ? 1 : 0
        ;; i32.and делает побитовое И, а сравнение с i32.const 0 выдает нативный 1 или 0
        (call $push
          (i32.ne
            (i32.and
              (local.get $bit_mask)
              (local.get $i))
            (i32.const 0))))
      ;; --- ВЕТКА FALSE: j за пределами 0..31, возвращаем 0 ---
      (else
        (call $push
          (i32.const 0)))))

  ;; ========================================================
  ;; Инструкция JBSC (Опкод 0x1E) — Условный переход назад, если 0
  ;; ========================================================
  (func (export "ir_JBSC")
    (local $cond i32)
    (local $pc1 i32)
    (local $current_pc i32)

    ;; 1. Вытаскиваем значение с вершины стека
    (local.set $cond
      (call $pop))

    ;; 2. Проверяем условие: if (pop() == 0)
    (if
      (i32.eqz
        (local.get $cond))
      ;; --- ВЕТКА TRUE (выполняем переход назад) ---
      (then
        ;; int pc1 = next(); (прочитает аргумент и сделает pc++)
        (local.set $pc1
          (call $next))

        ;; pc -= pc1;
        (local.set $current_pc
          (i32.load
            (global.get $PC_ADDR)))
        (i32.store
          (global.get $PC_ADDR)
          (i32.sub
            (local.get $current_pc)
            (local.get $pc1))))
      ;; --- ВЕТКА FALSE (else) ---
      (else
        ;; pc++; (просто пропускаем аргумент pc1, вставая на следующую инструкцию)
        (local.set $current_pc
          (i32.load
            (global.get $PC_ADDR)))
        (i32.store
          (global.get $PC_ADDR)
          (i32.add
            (local.get $current_pc)
            (i32.const 1))))))

  ;; ========================================================
  ;; Инструкция ABS (Опкод 0xA6) — Модуль числа (Absolute value)
  ;; ========================================================
  (func (export "ir_ABS")
    (local $i i32)
    (local.set $i
      (call $pop))
    ;; if (i < 0) push(-i) else push(i)
    (if
      (i32.lt_s
        (local.get $i)
        (i32.const 0))
      (then
        (call $push
          (i32.sub
            (i32.const 0)
            (local.get $i))))
      (else
        (call $push
          (local.get $i)))))

  ;; ========================================================
  ;; Инструкция NEG (Опкод 0xA7) — Смена знака (-pop())
  ;; ========================================================
  (func (export "ir_NEG")
    ;; Вычитаем из 0 верхнее значение стека и пушим обратно
    (call $push
      (i32.sub
        (i32.const 0)
        (call $pop))))

  ;; ========================================================
  ;; Инструкция OR (Опкод 0xA8) — Побитовое ИЛИ
  ;; ========================================================
  (func (export "ir_OR")
    (local $val2 i32) (local $val1 i32)
    (local.set $val2
      (call $pop))
    (local.set $val1
      (call $pop))
    (call $push
      (i32.or
        (local.get $val1)
        (local.get $val2))))

  ;; ========================================================
  ;; Инструкция AND (Опкод 0xA9) — Побитовое И
  ;; ========================================================
  (func (export "ir_AND")
    (local $val2 i32) (local $val1 i32)
    (local.set $val2
      (call $pop))
    (local.set $val1
      (call $pop))
    (call $push
      (i32.and
        (local.get $val1)
        (local.get $val2))))

  ;; ========================================================
  ;; Инструкция XOR (Опкод 0xAA) — Побитовое ИСКЛЮЧАЮЩЕЕ ИЛИ
  ;; ========================================================
  (func (export "ir_XOR")
    (local $val2 i32) (local $val1 i32)
    (local.set $val2
      (call $pop))
    (local.set $val1
      (call $pop))
    (call $push
      (i32.xor
        (local.get $val1)
        (local.get $val2))))

  ;; ========================================================
  ;; Инструкция BIC (Опкод 0xAB) — Очистка бит по маске (Bit Clear)
  ;; ========================================================
  (func (export "ir_BIC")
    (local $i i32) ;; Маска очистки, извлекается первым
    (local $val i32) ;; Число, извлекается вторым
    (local $not_i i32)

    (local.set $i
      (call $pop))
    (local.set $val
      (call $pop))

    ;; Реализуем ~i как i ^ 0xFFFFFFFF (в Wasm это константа -1)
    (local.set $not_i
      (i32.xor
        (local.get $i)
        (i32.const -1)))

    ;; push(val & ~i)
    (call $push
      (i32.and
        (local.get $val)
        (local.get $not_i))))

  ;; ========================================================
  ;; Инструкция LLA (Опкод 0x14) — Загрузка адреса локальной переменной
  ;; ========================================================
  (func (export "ir_LLA")
    (local $l_word i32)
    (local $offset i32)

    ;; 1. Читаем текущее значение регистра L (в словах) из памяти
    (local.set $l_word
      (i32.load
        (global.get $L_ADDR)))

    ;; 2. int offset = next(); (Считывает смещение и сдвигает PC на 1)
    (local.set $offset
      (call $next))

    ;; 3. push(l + offset); (Складываем словесные адреса и кладем на стек)
    (call $push
      (i32.add
        (local.get $l_word)
        (local.get $offset))))

  ;; ========================================================
  ;; Инструкция INC1 (Опкод 0xE4) — Инкремент значения в памяти на 1
  ;; ========================================================
  (func (export "ir_INC1")
    (local $i i32) ;; Словесный адрес ячейки
    (local $target_byte_addr i32)
    (local $max_safe_byte i32)
    (local $current_val i32)

    ;; 1. Извлекаем словесный адрес со стека выражений
    (local.set $i
      (call $pop))

    ;; 2. Переводим в байты: i * 4
    (local.set $target_byte_addr
      (i32.mul
        (local.get $i)
        (i32.const 4)))
    (local.set $max_safe_byte
      (i32.sub
        (global.get $MEM_SIZE)
        (i32.const 4)))

    ;; 3. МЯГКАЯ ВАЛИДАЦИЯ ГРАНИЦ
    (if
      (i32.or
        (i32.lt_s
          (local.get $target_byte_addr)
          (i32.const 0))
        (i32.gt_s
          (local.get $target_byte_addr)
          (local.get $max_safe_byte)))
      (then
        (i32.store
          (global.get $IPT_ADDR)
          (i32.const 3)))
      (else
        ;; Читаем, прибавляем 1 и записываем обратно
        (local.set $current_val
          (i32.load
            (local.get $target_byte_addr)))
        (i32.store
          (local.get $target_byte_addr)
          (i32.add
            (local.get $current_val)
            (i32.const 1))))))

  ;; ========================================================
  ;; Инструкция DEC1 (Опкод 0xE5) — Декремент значения в памяти на 1
  ;; ========================================================
  (func (export "ir_DEC1")
    (local $i i32)
    (local $target_byte_addr i32)
    (local $max_safe_byte i32)
    (local $current_val i32)

    (local.set $i
      (call $pop))
    (local.set $target_byte_addr
      (i32.mul
        (local.get $i)
        (i32.const 4)))
    (local.set $max_safe_byte
      (i32.sub
        (global.get $MEM_SIZE)
        (i32.const 4)))

    (if
      (i32.or
        (i32.lt_s
          (local.get $target_byte_addr)
          (i32.const 0))
        (i32.gt_s
          (local.get $target_byte_addr)
          (local.get $max_safe_byte)))
      (then
        (i32.store
          (global.get $IPT_ADDR)
          (i32.const 3)))
      (else
        ;; Читаем, вычитаем 1 и записываем обратно
        (local.set $current_val
          (i32.load
            (local.get $target_byte_addr)))
        (i32.store
          (local.get $target_byte_addr)
          (i32.sub
            (local.get $current_val)
            (i32.const 1))))))

  ;; ========================================================
  ;; Инструкция INC (Опкод 0xE6) — Инкремент ячейки памяти на заданное значение
  ;; ========================================================
  (func (export "ir_INC")
    (local $i i32) ;; Значение инкремента, извлекается ПЕРВЫМ
    (local $j i32) ;; Словесный адрес ячейки, извлекается ВТОРЫМ
    (local $target_byte_addr i32)
    (local $max_safe_byte i32)
    (local $current_val i32)

    ;; Извлекаем параметры в строгом порядке Java
    (local.set $i
      (call $pop))
    (local.set $j
      (call $pop))

    (local.set $target_byte_addr
      (i32.mul
        (local.get $j)
        (i32.const 4)))
    (local.set $max_safe_byte
      (i32.sub
        (global.get $MEM_SIZE)
        (i32.const 4)))

    (if
      (i32.or
        (i32.lt_s
          (local.get $target_byte_addr)
          (i32.const 0))
        (i32.gt_s
          (local.get $target_byte_addr)
          (local.get $max_safe_byte)))
      (then
        (i32.store
          (global.get $IPT_ADDR)
          (i32.const 3)))
      (else
        ;; Читаем, прибавляем i и записываем обратно
        (local.set $current_val
          (i32.load
            (local.get $target_byte_addr)))
        (i32.store
          (local.get $target_byte_addr)
          (i32.add
            (local.get $current_val)
            (local.get $i))))))

  ;; ========================================================
  ;; Инструкция DEC (Опкод 0xE7) — Декремент ячейки памяти на заданное значение
  ;; ========================================================
  (func (export "ir_DEC")
    (local $i i32) ;; Значение декремента, извлекается ПЕРВЫМ
    (local $j i32) ;; Словесный адрес ячейки, извлекается ВТОРЫМ
    (local $target_byte_addr i32)
    (local $max_safe_byte i32)
    (local $current_val i32)

    ;; Извлекаем параметры в строгом порядке Java
    (local.set $i
      (call $pop))
    (local.set $j
      (call $pop))

    (local.set $target_byte_addr
      (i32.mul
        (local.get $j)
        (i32.const 4)))
    (local.set $max_safe_byte
      (i32.sub
        (global.get $MEM_SIZE)
        (i32.const 4)))

    (if
      (i32.or
        (i32.lt_s
          (local.get $target_byte_addr)
          (i32.const 0))
        (i32.gt_s
          (local.get $target_byte_addr)
          (local.get $max_safe_byte)))
      (then
        (i32.store
          (global.get $IPT_ADDR)
          (i32.const 3)))
      (else
        ;; Читаем, вычитаем i и записываем обратно
        (local.set $current_val
          (i32.load
            (local.get $target_byte_addr)))
        (i32.store
          (local.get $target_byte_addr)
          (i32.sub
            (local.get $current_val)
            (local.get $i))))))

  ;; ========================================================
  ;; Инструкция SHL (Опкод 0x8C) — Битовый сдвиг влево
  ;; ========================================================
  (func (export "ir_SHL")
    (local $i i32)
    (local $val i32)

    ;; Извлекаем в порядке Java: сначала сдвиг, потом число
    (local.set $i
      (i32.and
        (call $pop)
        (i32.const 0x1F)))
    (local.set $val
      (call $pop))

    (call $push
      (i32.shl
        (local.get $val)
        (local.get $i))))

  ;; ========================================================
  ;; Инструкция SHR (Опкод 0x8D) — Арифметический сдвиг вправо
  ;; ========================================================
  (func (export "ir_SHR")
    (local $i i32)
    (local $val i32)

    (local.set $i
      (i32.and
        (call $pop)
        (i32.const 0x1F)))
    (local.set $val
      (call $pop))

    ;; Используем shr_s (signed) для сохранения знакового бита, как в Java (>>)
    (call $push
      (i32.shr_s
        (local.get $val)
        (local.get $i))))

  ;; ========================================================
  ;; Инструкция ROL (Опкод 0x8E) — Циклическое вращение влево
  ;; ========================================================
  (func (export "ir_ROL")
    (local $i i32)
    (local $val i32)

    (local.set $i
      (i32.and
        (call $pop)
        (i32.const 0x1F)))

    ;; Если i != 0, снимаем число и вращаем. Иначе число просто остается на вершине стека!
    (if
      (i32.ne
        (local.get $i)
        (i32.const 0))
      (then
        (local.set $val
          (call $pop))
        (call $push
          (i32.rotl
            (local.get $val)
            (local.get $i))))))

  ;; ========================================================
  ;; Инструкция ROR (Опкод 0x8F) — Циклическое вращение вправо
  ;; ========================================================
  (func (export "ir_ROR")
    (local $i i32)
    (local $val i32)

    (local.set $i
      (i32.and
        (call $pop)
        (i32.const 0x1F)))

    ;; Если i != 0, снимаем число и вращаем.
    (if
      (i32.ne
        (local.get $i)
        (i32.const 0))
      (then
        (local.set $val
          (call $pop))
        (call $push
          (i32.rotr
            (local.get $val)
            (local.get $i))))))

  ;; ========================================================
  ;; Инструкция BIT (Опкод 0xAD) — Сформировать маску бита (1 << i)
  ;; ========================================================
  (func (export "ir_BIT")
    (local $i i32)

    ;; 1. Извлекаем номер бита со стека выражений
    (local.set $i
      (call $pop))

    ;; 2. Валидация диапазона: if (i >= 0 && i < 32)
    ;; В беззнаковом режиме lt_u отсекает отрицательные числа и числа >= 32
    (if
      (i32.lt_u
        (local.get $i)
        (i32.const 32))
      ;; --- ВЕТКА TRUE: Бит в валидном диапазоне ---
      (then
        ;; Нативно формируем бит 1 << i и отправляем в push
        (call $push
          (i32.shl
            (i32.const 1)
            (local.get $i))))
      ;; --- ВЕТКА FALSE: Ошибка индекса бита ---
      (else
        ;; ipt = 0x4A;
        (i32.store
          (global.get $IPT_ADDR)
          (i32.const 0x4A)))))

  ;; ========================================================
  ;; Вспомогательная функция QABS (Исправленная версия)
  ;; ========================================================
  (func $qabs (param $x i32) (result i32)
    ;; Явно говорим компилятору, что этот блок if возвращает i32 на стек
    (if (result i32)
      (i32.ge_s
        (local.get $x)
        (i32.const 0))
      (then
        (local.get $x))
      (else
        (i32.sub
          (i32.const 0)
          (local.get $x)))))

  ;; ========================================================
  ;; Универсальный алгоритм деления в столбик _idiv
  ;; @param $want_remainder : 1 = вернуть остаток (x), 0 = вернуть частное (z)
  ;; ========================================================
  (func $_idiv_internal
    (param $x_in i32) (param $y_in i32) (param $want_remainder i32) (result i32)
    (local $x i32)
    (local $y i32)
    (local $z i32)
    (local $bt i32)

    (local.set $x
      (local.get $x_in))
    (local.set $y
      (local.get $y_in))
    (local.set $z
      (i32.const 0))
    (local.set $bt
      (i32.const 1))

    ;; 1. Цикл по qabs(x) > qabs(y)
    (block $exit_while
      (loop $while_loop
        (br_if $exit_while
          (i32.le_s
            (call $qabs
              (local.get $x))
            (call $qabs
              (local.get $y))))

        (local.set $bt
          (i32.shl
            (local.get $bt)
            (i32.const 1)))
        (local.set $y
          (i32.shl
            (local.get $y)
            (i32.const 1)))
        (br $while_loop)))

    ;; 2. Главный бесконечный цикл восстановления остатка
    (block $exit_for
      (loop $for_loop
        ;; if ((x >= 0) == (y >= 0))
        (if
          (i32.eq
            (i32.ge_s
              (local.get $x)
              (i32.const 0))
            (i32.ge_s
              (local.get $y)
              (i32.const 0)))
          (then
            ;; if (y < 0)
            (if
              (i32.lt_s
                (local.get $y)
                (i32.const 0))
              (then
                ;; if (x <= y) { x = x - y; z = z + bt; }
                (if
                  (i32.le_s
                    (local.get $x)
                    (local.get $y))
                  (then
                    (local.set $x
                      (i32.sub
                        (local.get $x)
                        (local.get $y)))
                    (local.set $z
                      (i32.add
                        (local.get $z)
                        (local.get $bt))))))
              (else
                ;; if (x >= y) { x = x - y; z = z + bt; }
                (if
                  (i32.ge_s
                    (local.get $x)
                    (local.get $y))
                  (then
                    (local.set $x
                      (i32.sub
                        (local.get $x)
                        (local.get $y)))
                    (local.set $z
                      (i32.add
                        (local.get $z)
                        (local.get $bt))))))))
          (else
            ;; if (y < 0)
            (if
              (i32.lt_s
                (local.get $y)
                (i32.const 0))
              (then
                ;; if (x > 0) { x = x + y; z = z - bt; }
                (if
                  (i32.gt_s
                    (local.get $x)
                    (i32.const 0))
                  (then
                    (local.set $x
                      (i32.add
                        (local.get $x)
                        (local.get $y)))
                    (local.set $z
                      (i32.sub
                        (local.get $z)
                        (local.get $bt))))))
              (else
                ;; if (x < 0) { x = x + y; z = z - bt; }
                (if
                  (i32.lt_s
                    (local.get $x)
                    (i32.const 0))
                  (then
                    (local.set $x
                      (i32.add
                        (local.get $x)
                        (local.get $y)))
                    (local.set $z
                      (i32.sub
                        (local.get $z)
                        (local.get $bt)))))))))

        ;; if (bt == 1) break;
        (br_if $exit_for
          (i32.eq
            (local.get $bt)
            (i32.const 1)))

        (local.set $bt
          (i32.shr_s
            (local.get $bt)
            (i32.const 1)))

        ;; Коррекция y при сдвиге вправо со сдвигом знака
        (if
          (i32.gt_s
            (local.get $y)
            (i32.const 0))
          (then
            (local.set $y
              (i32.shr_s
                (i32.and
                  (local.get $y)
                  (i32.const -2))
                (i32.const 1))))
          (else
            (local.set $y
              (i32.shr_s
                (i32.or
                  (local.get $y)
                  (i32.const 1))
                (i32.const 1)))))

        (br $for_loop)))

    ;; 3. Возвращаем либо остаток (x), либо частное (z)
    ;; Добавляем (result i32), чтобы Wasm знал, что этот if легально возвращает число
    (if (result i32)
      (local.get $want_remainder)
      (then
        (local.get $x))
      (else
        (local.get $z))))

  ;; ========================================================
  ;; Инструкция MOD (Опкод 0xAF) — Теперь через общую функцию
  ;; ========================================================
  (func (export "ir_MOD")
    (local $sp i32)
    (local $val2 i32) ;; y
    (local $val1 i32) ;; x

    (local.set $sp
      (i32.load
        (global.get $SP_ADDR)))

    (if
      (i32.le_s
        (local.get $sp)
        (i32.const 1))
      (then
        (i32.store
          (global.get $IPT_ADDR)
          (i32.const 0x4C)))
      (else
        (local.set $val2
          (call $pop))
        (local.set $val1
          (call $pop))

        (if
          (i32.eqz
            (local.get $val1))
          (then
            (i32.store
              (global.get $IPT_ADDR)
              (i32.const 0x41))
            (call $push
              (i32.const 0)))
          (else
            ;; Вызываем функцию, запрашивая остаток (want_remainder = 1)
            (call $push
              (call $_idiv_internal
                (local.get $val1)
                (local.get $val2)
                (i32.const 1))))))))

  ;; ========================================================
  ;; Инструкция DIV (Опкод 0x8B) — Деление (частное от _idiv)
  ;; ========================================================
  (func (export "ir_DIV")
    (local $sp i32)
    (local $val2 i32) ;; y (верхний элемент стека)
    (local $val1 i32) ;; x (предыдущий элемент стека)

    ;; 1. Читаем текущий SP
    (local.set $sp
      (i32.load
        (global.get $SP_ADDR)))

    ;; 2. Проверяем условие нехватки элементов: if (sp <= 1)
    (if
      (i32.le_s
        (local.get $sp)
        (i32.const 1))
      (then
        (i32.store
          (global.get $IPT_ADDR)
          (i32.const 0x4C)))
      (else
        ;; Извлекаем элементы со стека в правильном порядке
        (local.set $val2
          (call $pop))
        (local.set $val1
          (call $pop))

        ;; 3. Если делимое x == 0 (по вашей семантике: else if (astack[sp-1] == 0))
        (if
          (i32.eqz
            (local.get $val1))
          (then
            (i32.store
              (global.get $IPT_ADDR)
              (i32.const 0x41))
            (call $push
              (i32.const 0)))
          (else
            ;; 4. Успешный расчет: вызываем общую функцию деления,
            ;; запрашивая ЧАСТНОЕ (want_remainder = 0)
            (call $push
              (call $_idiv_internal
                (local.get $val1)
                (local.get $val2)
                (i32.const 0))))))))

  ;; ========================================================
  ;; Инструкция GB1 (Опкод 0xC5) — Загрузка слова по адресу из регистра L
  ;; ========================================================
  (func (export "ir_GB1")
    (local $l_word i32) ;; Значение регистра L (в словах)
    (local $target_byte_addr i32)
    (local $max_safe_byte i32)
    (local $loaded_word i32)

    ;; 1. Читаем текущее значение регистра L из памяти регистров
    (local.set $l_word
      (i32.load
        (global.get $L_ADDR)))

    ;; 2. Переводим словесный адрес в байтовый: L * 4
    (local.set $target_byte_addr
      (i32.mul
        (local.get $l_word)
        (i32.const 4)))
    (local.set $max_safe_byte
      (i32.sub
        (global.get $MEM_SIZE)
        (i32.const 4)))

    ;; 3. МЯГКАЯ ВАЛИДАЦИЯ ГРАНИЦ В ПАМЯТИ
    (if
      (i32.or
        (i32.lt_s
          (local.get $target_byte_addr)
          (i32.const 0))
        (i32.gt_s
          (local.get $target_byte_addr)
          (local.get $max_safe_byte)))
      ;; --- ВЕТКА TRUE: Выход за границы ---
      (then
        (i32.store
          (global.get $IPT_ADDR)
          (i32.const 3))
        (local.set $loaded_word
          (i32.const 0)))
      ;; --- ВЕТКА FALSE: Безопасно читаем 32-битное слово ---
      (else
        (local.set $loaded_word
          (i32.load
            (local.get $target_byte_addr)))))

    ;; 4. Кладем полученное слово (или 0) на стек выражений
    (call $push
      (local.get $loaded_word)))

  ;; ========================================================
  ;; Инструкция GB (Опкод 0xC4) — Получение базы кадра на N уровней выше
  ;; ========================================================
  (func (export "ir_GB")
    (local $i i32) ;; Текущий указатель кадра (в словах)
    (local $j i32) ;; Количество уровней для подъема (счетчик)
    (local $target_byte_addr i32)
    (local $max_safe_byte i32)

    ;; 1. int i = l; (Начинаем с текущего регистра L)
    (local.set $i
      (i32.load
        (global.get $L_ADDR)))

    ;; 2. int j = next(); (Читаем байт аргумента из кода)
    (local.set $j
      (call $next))

    (local.set $max_safe_byte
      (i32.sub
        (global.get $MEM_SIZE)
        (i32.const 4)))

    ;; 3. Цикл прохода по цепочке кадров: while (j > 0)
    (block $exit_gb_loop
      (loop $gb_loop
        ;; Условие выхода: если j <= 0, выходим из цикла
        (br_if $exit_gb_loop
          (i32.le_s
            (local.get $j)
            (i32.const 0)))

        ;; Переводим текущий словесный адрес кадра в байты: i * 4
        (local.set $target_byte_addr
          (i32.mul
            (local.get $i)
            (i32.const 4)))

        ;; МЯГКАЯ ВАЛИДАЦИЯ ГРАНИЦ: проверяем адрес перед чтением mem(i)
        (if
          (i32.or
            (i32.lt_s
              (local.get $target_byte_addr)
              (i32.const 0))
            (i32.gt_s
              (local.get $target_byte_addr)
              (local.get $max_safe_byte)))
          ;; --- ВЕТКА TRUE: Ошибка адресации цепочки ---
          (then
            (i32.store
              (global.get $IPT_ADDR)
              (i32.const 3))
            (local.set $i
              (i32.const 0))
            (br $exit_gb_loop) ;; Аварийно прерываем цикл
          )
          ;; --- ВЕТКА FALSE: Все хорошо, читаем указатель статического кадра ---
          (else
            ;; i = mem(i)
            (local.set $i
              (i32.load
                (local.get $target_byte_addr)))))

        ;; j-- (уменьшаем счетчик уровней)
        (local.set $j
          (i32.sub
            (local.get $j)
            (i32.const 1)))

        ;; Повторяем цикл
        (br $gb_loop)))

    ;; 4. push(i); (Кладем вычисленный адрес кадра на стек выражений)
    (call $push
      (local.get $i)))
    
    
    
    
) ;; module end
