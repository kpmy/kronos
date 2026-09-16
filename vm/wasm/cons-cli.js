import {VirtualConsole} from "./cons.js";

export class VirtualConsoleCli extends VirtualConsole {

    constructor(addr, ipt) {
        super(addr, ipt);

        if (process.stdin.isTTY) {
            process.stdin.setRawMode(true);
        }
        process.stdin.resume();
        process.stdin.setEncoding('utf8');

        // Слушаем ввод от пользователя
        process.stdin.on('data', (key) => {
            // Обработка Ctrl+C для штатного выхода из эмулятора
            if (key === '\u0003') {
                console.log("\n[JS Host] terminated (Ctrl+C)...");
                process.exit();
            }

            // Переводим символ в ASCII код и кладем в очередь
            const charCode = key.charCodeAt(0);
            //console.log(charCode);
            this.read(charCode);
        });

    }

    write(output) {
        process.stdout.write(output);
    }
}
