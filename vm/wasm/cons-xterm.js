import {VirtualConsole} from "./cons.js";

export class VirtualWebConsole extends VirtualConsole {

    term

    constructor(term, addr, inp) {
        super(addr, inp);
        this.term = term;

        term.onData(e => {
            switch (e) {
                case '\u007F': // Backspace (DEL)
                    //term.write('\b \b');
                    this.read(8)
                    break;
                default: // Все остальные символы
                    console.log(`key ${e.charCodeAt(0).toString(16)}`);
                    this.read(e.charCodeAt(0))
            }
        });
    }

    write(output) {
        this.term.write(output);
    }

}
