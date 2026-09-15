import m from 'mithril';
import $ from 'cash-dom';

// Импортируем компоненты Material
import '@material/web/button/filled-button.js';
import '@material/web/checkbox/checkbox.js';
import '@material/web/list/list.js';
import '@material/web/list/list-item.js';


import {Terminal} from 'xterm';
import {VirtualMachine} from '../vm.js'
import {VirtualWebConsole} from "../cons-xterm.js";
import {VirtualWebDisk} from "../disk-web.js";


async function initVirtualMachine(term) {
    const MEMORY_SIZE = 4 * 1024 * 1024;

    const response = await fetch('assets/core.wasm');
    const wasmModule = await WebAssembly.compile(await response.arrayBuffer());

    let vm = new VirtualMachine(MEMORY_SIZE, new VirtualWebConsole(term, 0xFB8, 0x0C));
    vm.core = wasmModule;
    await Promise.all(Array.from([await loadStaticAsFile('assets/disks/xd0.dsk'), await loadStaticAsFile('assets/disks/xd1.dsk')]).map(async (dsk) => {
        let disk = new VirtualWebDisk(dsk);
        await disk.load()
        vm.addDisk(disk);
    }))
    await vm.readBooter(1);
    return vm;
}

let globalVM;

async function waitVirtualMachine() {
    if (globalVM) {
        await globalVM.runSafe()
    } else {
        setTimeout(waitVirtualMachine, 1000);
    }
}

// Компонент Терминала
const TerminalComponent = () => {
    let term = null;

    return {
        // oncreate вызывается сразу после того, как Mithril отрендерил HTML в DOM
        oncreate: async (vnode) => {
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
                term.writeln('kronos.wasm');

                globalVM = await initVirtualMachine(term);
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

async function loadStaticAsFile(url, fileName) {
    const response = await fetch(url);
    if (!response.ok) throw new Error(`Ошибка сети: ${response.status}`);
    // 1. Получаем Blob (сырые данные с MIME-типом)
    const blob = await response.blob();
    // 2. Оборачиваем Blob в стандартный веб-объект File
    return new File([blob], fileName, {type: blob.type});
}

// Главный компонент приложения
const App = () => {
    return {
        oncreate: async (vnode) => {

        },
        view: () => (
            <main>
                <h1>КРОНОС</h1>
                <p>Виртуальная машина на WebAssembly</p>
                <md-filled-button onclick={() => window.location.reload()}>
                    RESET
                </md-filled-button>
                {/* Рендерим наш терминал */}
                <TerminalComponent />
                <p>Вероятно, для входа в систему доступны пользователи (вход без пароля):
                    <ul>
                        <li>su /usr  </li>
                        <li>guest /  (вход без пароля)</li>
                        <li>sys         /sys</li>
                    </ul>
                </p>
                <p>Исследовать на GitHub <a href="https://github.com/kpmy/kronos">https://github.com/kpmy/kronos</a></p>
            </main>
        )
    };
};

// Монтируем через cash-dom
const $root = $('#app');
if ($root.length) {
    m.mount($root[0], App);
}

await waitVirtualMachine();
