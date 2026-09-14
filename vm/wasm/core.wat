(module
        (import "env" "memory" (memory $mem 1))
        ;; НАША ОТЛАДОЧНАЯ ФУНКЦИЯ: принимает (id_точки, значение)
        (import "env" "log_debug" (func $log_debug (param i32 i32)))

        ;; Абсолютные адреса регистров в WebAssembly.Memory (База + Индекс * 4)
        (global $IPT_ADDR (mut i32) (i32.const 0))   ;; 4  (Индекс 1) //код прерывания
        (global $SP_ADDR (mut i32) (i32.const 0))    ;; 8  (Индекс 2) //указатель на стек выражений (верхний элемент)
        (global $PC_ADDR (mut i32) (i32.const 0))    ;; 12 (Индекс 3) //указатель на инструкцию
        (global $IR_ADDR (mut i32) (i32.const 0))    ;; 16 (Индекс 4)  //инструкция
        (global $P_ADDR (mut i32) (i32.const 0))     ;; 20 (Индекс 5) //память процесса
        (global $L_ADDR (mut i32) (i32.const 0))     ;; 24 (Индекс 6) //область локальных данных текущей процедуры на стеке
        (global $G_ADDR (mut i32) (i32.const 0))     ;; 28 (Индекс 7) //область глобальных данных модуля
        (global $M_ADDR (mut i32) (i32.const 0))     ;; 32 (Индекс 8) //маска прерываний
        (global $H_ADDR (mut i32) (i32.const 0))     ;; 36 (Индекс 9) //конец процедурного стека
        (global $S_ADDR (mut i32) (i32.const 0))     ;; 40 (Индекс 10)  //указатель на процедурный стек (верхний элемент)
        (global $F_ADDR (mut i32) (i32.const 0))     ;; 44 (Индекс 11)  //указатель на начало сегмента кода текущей процедуры
        (global $CODE_ADDR (mut i32) (i32.const 0))  ;; 48 (Индекс 12) //указатель на инструкцию
        (global $STACK_ADDR (mut i32) (i32.const 0)) ;; 128 (Индекс 32) //СТЕК

        (global $ASTACK_SIZE (mut i32) (i32.const 0)) ;; размер стека
        (global $MEM_SIZE (mut i32) (i32.const 0)) ;; размер памяти

        ;; Функция PUSH: принимает значение i32
          (func $push (param $value i32)
            (local $sp i32)

            ;; 1. let sp = this.memory.getReg(SP)
            (local.set $sp (i32.load (global.get $SP_ADDR)))

            ;; 2. Проверка условий: if (sp >= 0 && sp < AStackSize)
            ;; Примечание: в вашем JS было (sp <= 0), но судя по логике (sp + 1) и (STACK + sp),
            ;; индекс должен быть неотрицательным: sp >= 0
            (if (i32.and
                  (i32.ge_s (local.get $sp) (i32.const 0))
                  (i32.lt_s (local.get $sp) (global.get $ASTACK_SIZE)) ;; Подставьте вашу константу AStackSize
                )
              ;; --- ВЕТКА IF: всё хорошо, пишем в стек ---
              (then
                ;; this.memory.setReg(i32, STACK + sp)
                ;; Вычисляем физический адрес: STACK_ADDR + (sp * 4)
                (i32.store
                  (i32.add
                    (global.get $STACK_ADDR)
                    (i32.mul (local.get $sp) (i32.const 4))
                  )
                  (local.get $value)
                )

                ;; this.memory.setReg(sp + 1, SP)
                (i32.store
                  (global.get $SP_ADDR)
                  (i32.add (local.get $sp) (i32.const 1))
                )
              )
              ;; --- ВЕТКА ELSE: выход за границы стека ---
              (else
                ;; this.memory.setReg(0x4C, IPT)
                (i32.store (global.get $IPT_ADDR) (i32.const 0x4C))
              )
            )
          )

    ;; ========================================================
    ;; Функция POP (для контроля структуры, без изменений)
    ;; ========================================================
    (func $pop (export "pop") (result i32)
      (local $sp i32)
      (local $top_val i32)

      (local.set $sp (i32.load (global.get $SP_ADDR)))

      (if (i32.gt_s (local.get $sp) (i32.const 0))
        (then
          (local.set $sp (i32.sub (local.get $sp) (i32.const 1)))
          (local.set $top_val
            (i32.load (i32.add (global.get $STACK_ADDR) (i32.mul (local.get $sp) (i32.const 4))))
          )
          (i32.store (global.get $SP_ADDR) (local.get $sp))
        )
        (else
          (i32.store (global.get $IPT_ADDR) (i32.const 0x4C))
          (local.set $top_val (i32.const 0))
        )
      )
      (local.get $top_val)
    )

          ;; Функция next: переводит CODE в байты, складывает с байтовым PC,
          ;; читает 1 байт, сдвигает PC на 1 и возвращает результат.
          (func $next (result i32)
            (local $code_words i32)  ;; Значение регистра CODE в словах
            (local $code_bytes i32)  ;; Значение регистра CODE, переведенное в байты
            (local $pc_offset i32)   ;; Оффсет из регистра PC в байтах
            (local $phys_addr i32)   ;; Итоговый физический адрес для чтения
            (local $fetched_val i32) ;; Считанный байт аргумента

            ;; 1. Читаем значение CODE (в словах) из памяти регистров
            (local.set $code_words (i32.load (global.get $CODE_ADDR)))

            ;; 2. Переводим слова в байты: CODE * 4
            (local.set $code_bytes (i32.mul (local.get $code_words) (i32.const 4)))

            ;; 3. Читаем текущее значение PC (в байтах)
            (local.set $pc_offset (i32.load (global.get $PC_ADDR)))

            ;; 4. Вычисляем физический адрес: (CODE * 4) + PC
            (local.set $phys_addr (i32.add (local.get $code_bytes) (local.get $pc_offset)))

            ;; 5. Читаем 1 байт по вычисленному адресу
            (local.set $fetched_val (i32.load8_u (local.get $phys_addr)))

            ;; 6. Увеличиваем байтовый оффсет PC на 1 и сохраняем обратно в регистр PC
            (i32.store
              (global.get $PC_ADDR)
              (i32.add (local.get $pc_offset) (i32.const 1))
            )

            ;; 7. Возвращаем считанный байт
            (local.get $fetched_val)
          )

        (func (export "init_vm") (param $total_pages i32) (param $stack_size i32)
            ;; Локальная переменная для хранения базового адреса начала регистров
            (local $reg_base i32)

            ;; 1. Вычисляем адрес начала регистров: (TOTAL_PAGES - 1) * 65536
            ;; Для TOTAL_PAGES = 65, это даст ровно 4194304 (начало 65-й страницы)
            (local.set $reg_base
                (i32.mul
                    (i32.sub (local.get $total_pages) (i32.const 1))
                    (i32.const 65536)
                )
            )

            ;; 2. Инициализируем абсолютные адреса регистров (База + Смещение в байтах)
            (global.set $IPT_ADDR   (i32.add (local.get $reg_base) (i32.const 4)))
            (global.set $SP_ADDR    (i32.add (local.get $reg_base) (i32.const 8)))
            (global.set $PC_ADDR    (i32.add (local.get $reg_base) (i32.const 12)))
            (global.set $IR_ADDR    (i32.add (local.get $reg_base) (i32.const 16)))
            (global.set $P_ADDR     (i32.add (local.get $reg_base) (i32.const 20)))
            (global.set $L_ADDR     (i32.add (local.get $reg_base) (i32.const 24)))
            (global.set $G_ADDR     (i32.add (local.get $reg_base) (i32.const 28)))
            (global.set $M_ADDR     (i32.add (local.get $reg_base) (i32.const 32)))
            (global.set $H_ADDR     (i32.add (local.get $reg_base) (i32.const 36)))
            (global.set $S_ADDR     (i32.add (local.get $reg_base) (i32.const 40)))
            (global.set $F_ADDR     (i32.add (local.get $reg_base) (i32.const 44)))
            (global.set $CODE_ADDR  (i32.add (local.get $reg_base) (i32.const 48)))
            (global.set $STACK_ADDR (i32.add (local.get $reg_base) (i32.const 128)))

            (global.set $ASTACK_SIZE (local.get $stack_size))
            (global.set $MEM_SIZE (local.get $reg_base))
        )

        ;; Динамический JIT-код для конкретной инструкции LIB
        (func (export "ir_LIB")
            (call $push (call $next))
        )

        ;; Функция LSW: модифицирует верхнее значение стека, прибавляя (ir & 0xF),
        ;; и загружает по этому адресу 32-битное слово.
        (func $ir_LSW (export "ir_LSW")
            (local $ir i32)
              (local $sp_idx i32)
              (local $top_val_addr i32)
              (local $target_word_addr i32) ;; Гостевой адрес в СЛОВАХ
              (local $target_byte_addr i32) ;; Гостевой адрес в БАЙТАХ (для Wasm)
              (local $loaded_word i32)

              ;; 1. Читаем инструкцию из регистра IR
              (local.set $ir (i32.load (global.get $IR_ADDR)))

              ;; 2. Находим sp - 1 (индекс верхнего элемента стека)
              (local.set $sp_idx (i32.sub (i32.load (global.get $SP_ADDR)) (i32.const 1)))

              ;; 3. Вычисляем физический адрес ячейки astack[sp-1] в памяти Wasm
              (local.set $top_val_addr (i32.add (global.get $STACK_ADDR) (i32.mul (local.get $sp_idx) (i32.const 4))))

              ;; 4. Вычисляем гостевой адрес в СЛОВАХ: astack[sp-1] + (ir & 0xF)
              (local.set $target_word_addr
                (i32.add
                  (i32.load (local.get $top_val_addr))              ;; Значение слова из стека
                  (i32.and (local.get $ir) (i32.const 0x0F))        ;; Смещение (ir & 0xF) в словах
                )
              )

              ;; 5. ВАЖНЫЙ ШАГ: Переводим словесный адрес гостя в байтовый для WebAssembly (Умножаем на 4)
              (local.set $target_byte_addr (i32.mul (local.get $target_word_addr) (i32.const 4)))

              ;; 6. Загружаем 32-битное слово по правильному байтовому адресу
              (local.set $loaded_word (i32.load (local.get $target_byte_addr)))

              ;; 7. Перезаписываем вершину стека
              (i32.store (local.get $top_val_addr) (local.get $loaded_word))
        )

        ;; ========================================================
          ;; 16 пустых экспортных оберток для вашего JS-диспетчера
          ;; ========================================================
          (func (export "ir_LSW0") (call $ir_LSW))
          (func (export "ir_LSW1") (call $ir_LSW))
          (func (export "ir_LSW2") (call $ir_LSW))
          (func (export "ir_LSW3") (call $ir_LSW))
          (func (export "ir_LSW4") (call $ir_LSW))
          (func (export "ir_LSW5") (call $ir_LSW))
          (func (export "ir_LSW6") (call $ir_LSW))
          (func (export "ir_LSW7") (call $ir_LSW))
          (func (export "ir_LSW8") (call $ir_LSW))
          (func (export "ir_LSW9") (call $ir_LSW))
          (func (export "ir_LSWA") (call $ir_LSW))
          (func (export "ir_LSWB") (call $ir_LSW))
          (func (export "ir_LSWC") (call $ir_LSW))
          (func (export "ir_LSWD") (call $ir_LSW))
          (func (export "ir_LSWE") (call $ir_LSW))
          (func (export "ir_LSWF") (call $ir_LSW))

  ;; ========================================================
    ;; Обновленная инструкция COPT (Опкод 0xB5) — Чистый вызов
    ;; ========================================================
    (func (export "ir_COPT")
      (local $val i32)

      ;; 1. Вытаскиваем верхнее значение
      (local.set $val (call $pop))

      ;; 2. Клади его обратно дважды (параметры размеров больше не нужны!)
      (call $push (local.get $val))
      (call $push (local.get $val))
    )

;; ========================================================
  ;; Единая внутренняя логика LI (Load Immediate)
  ;; ========================================================
  (func $ir_LI
    (local $ir i32)

    ;; 1. Читаем инструкцию, которую JS уже защелкнул в регистре IR
    (local.set $ir (i32.load (global.get $IR_ADDR)))

    ;; 2. Маскируем младшие 4 бита (ir & 0xF) и отправляем результат в push
    (call $push (i32.and (local.get $ir) (i32.const 0x0F)))
  )

  ;; ========================================================
  ;; 16 пустых экспортных оберток для вашего JS-диспетчера
  ;; ========================================================
  (func (export "ir_LI0") (call $ir_LI))
  (func (export "ir_LI1") (call $ir_LI))
  (func (export "ir_LI2") (call $ir_LI))
  (func (export "ir_LI3") (call $ir_LI))
  (func (export "ir_LI4") (call $ir_LI))
  (func (export "ir_LI5") (call $ir_LI))
  (func (export "ir_LI6") (call $ir_LI))
  (func (export "ir_LI7") (call $ir_LI))
  (func (export "ir_LI8") (call $ir_LI))
  (func (export "ir_LI9") (call $ir_LI))
  (func (export "ir_LI0A") (call $ir_LI))
  (func (export "ir_LI0B") (call $ir_LI))
  (func (export "ir_LI0C") (call $ir_LI))
  (func (export "ir_LI0D") (call $ir_LI))
  (func (export "ir_LI0E") (call $ir_LI))
  (func (export "ir_LI0F") (call $ir_LI))

 ;; ========================================================
  ;; Инструкция EQU (Опкод 0xA4) — Сравнение двух верхних элементов стека
  ;; ========================================================
  (func (export "ir_EQU")
    (local $sp i32)
    (local $val2 i32)  ;; Верхний элемент (astack[sp])
    (local $val1 i32)  ;; Предыдущий элемент (astack[sp-1])

    ;; 1. Читаем текущее значение SP из памяти регистров
    (local.set $sp (i32.load (global.get $SP_ADDR)))

    ;; 2. Проверяем условие: if (sp <= 1)
    (if (i32.le_s (local.get $sp) (i32.const 1))
      (then
        ;; Записываем код ошибки в регистр прерывания
        (i32.store (global.get $IPT_ADDR) (i32.const 0x4C))
      )
      (else
        ;; Извлекаем верхнее значение (val2 = astack[sp])
        (local.set $val2 (call $pop))

        ;; Извлекаем второе значение (val1 = astack[sp-1])
        (local.set $val1 (call $pop))

        ;; Сравниваем их: val1 == val2 ? 1 : 0
        ;; Результат сравнения сразу отправляем в метод push()
        (if (i32.eq (local.get $val1) (local.get $val2))
          (then
            (call $push (i32.const 1))
          )
          (else
            (call $push (i32.const 0))
          )
        )
      )
    )
  )

 ;; ========================================================
  ;; Инструкция JFSC (Опкод 0x1A) — Точная Java-семантика
  ;; ========================================================
  (func (export "ir_JFSC")
    (local $cond i32)
    (local $pc1 i32)
    (local $current_pc i32)

    ;; 1. Вытаскиваем значение с вершины стека
    (local.set $cond (call $pop))

    ;; 2. Проверяем условие: if (pop() == 0)
    (if (i32.eqz (local.get $cond))
      ;; --- ВЕТКА TRUE ---
      (then
        ;; int pc1 = next(); (прочитает аргумент и сделает pc++)
        (local.set $pc1 (call $next))

        ;; pc += pc1;
        (local.set $current_pc (i32.load (global.get $PC_ADDR)))
        (i32.store
          (global.get $PC_ADDR)
          (i32.add (local.get $current_pc) (local.get $pc1))
        )
      )
      ;; --- ВЕТКА FALSE (else) ---
      (else
        ;; pc++; (просто сдвигаем PC на 1 байт вперед относительно начала инструкции)
        (local.set $current_pc (i32.load (global.get $PC_ADDR)))
        (i32.store
          (global.get $PC_ADDR)
          (i32.add (local.get $current_pc) (i32.const 1))
        )
      )
    )
  )

  ;; ========================================================
  ;; Инструкция STOT (Опкод 0xE8) — Сохранение на процедурный стек
  ;; ========================================================
  (func (export "ir_STOT")
    (local $s i32)
    (local $h i32)
    (local $val i32)
    (local $phys_addr i32)

    ;; 1. Читаем текущие значения регистров S и H
    (local.set $s (i32.load (global.get $S_ADDR)))
    (local.set $h (i32.load (global.get $H_ADDR)))

    ;; 2. Проверяем условие переполнения: if (s + 1 > h)
    (if (i32.gt_s (i32.add (local.get $s) (i32.const 1)) (local.get $h))
      ;; --- ВЕТКА TRUE (Переполнение процедурного стека) ---
      (then
        ;; pc-- (возвращаем PC на начало этой инструкции)
        (i32.store
          (global.get $PC_ADDR)
          (i32.sub (i32.load (global.get $PC_ADDR)) (i32.const 1))
        )
        ;; ipt = 0x40
        (i32.store (global.get $IPT_ADDR) (i32.const 0x40))
      )
      ;; --- ВЕТКА FALSE (Безопасная запись) ---
      (else
        ;; Извлекаем значение из стека выражений через pop()
        (local.set $val (call $pop))

        ;; Вычисляем физический байтовый адрес в памяти: s * 4
        (local.set $phys_addr (i32.mul (local.get $s) (i32.const 4)))

        ;; mem(s, pop()) -> записываем 32-битное слово в память
        (i32.store (local.get $phys_addr) (local.get $val))

        ;; s++ -> увеличиваем регистр S на 1 (слово) и сохраняем обратно
        (i32.store (global.get $S_ADDR) (i32.add (local.get $s) (i32.const 1)))
      )
    )
  )

    ) ;; module end

