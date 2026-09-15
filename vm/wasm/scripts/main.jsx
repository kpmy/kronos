import m from 'mithril';
import $ from 'cash-dom';
import { Terminal } from 'xterm';

// Импортируем компоненты Material
import '@material/web/button/filled-button.js';
import '@material/web/checkbox/checkbox.js';

// Компонент Терминала
const TerminalComponent = () => {
    let term = null;

    return {
        // oncreate вызывается сразу после того, как Mithril отрендерил HTML в DOM
        oncreate: (vnode) => {
            // Используем cash для поиска контейнера терминала внутри нашего компонента
            const $container = $(vnode.dom).find('.terminal-instance');

            if ($container.length) {
                // Создаем терминал с кастомными настройками
                term = new Terminal({
                    cursorBlink: true,
                    fontFamily: 'Courier New, Courier, monospace',
                    fontSize: 14,
                    theme: {
                        background: '#1e1e1e'
                    }
                });

                // Открываем терминал в найденном DOM-элементе (берем нативный Node через)
                term.open($container[0]);

                // Стартовый текст
                term.writeln('Добро пожаловать в xterm.js!');
                term.write('\r\n$ ');

                // Простейшая обработка ввода (Echo-режим)
                let currentLine = '';
                term.onData(e => {
                    switch (e) {
                        case '\r': // Enter
                            term.writeln('');
                            if (currentLine.trim() === 'help') {
                                term.writeln('Доступные команды: help, clear');
                            } else if (currentLine.trim() === 'clear') {
                                term.clear();
                            } else if (currentLine) {
                                term.writeln(`Вы ввели: ${currentLine}`);
                            }
                            term.write('$ ');
                            currentLine = '';
                            break;
                        case '\u007F': // Backspace (DEL)
                            if (currentLine.length > 0) {
                                currentLine = currentLine.slice(0, -1);
                                term.write('\b \b');
                            }
                            break;
                        default: // Все остальные символы
                            currentLine += e;
                            term.write(e);
                    }
                });
            }
        },
        // Уничтожаем инстанс терминала при удалении компонента, чтобы не было утечек памяти
        onremove: () => {
            if (term) term.dispose();
        },
        view: () => (
            <div class="terminal-container">
                {/* Сюда xterm.js встроит холст терминала */}
                <div class="terminal-instance"></div>
            </div>
        )
    };
};

// Главный компонент приложения
const App = () => {
    return {
        view: () => (
            <main>
                <h1>Mithril + Material + Xterm.js</h1>
                <md-filled-button onclick={() => alert('Кнопка сверху работает!')}>
                    Material Кнопка
                </md-filled-button>

                {/* Рендерим наш терминал */}
                <TerminalComponent />
            </main>
        )
    };
};

// Монтируем через cash-dom
const $root = $('#app');
if ($root.length) {
    m.mount($root[0], App);
}
