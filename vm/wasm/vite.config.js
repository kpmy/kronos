import { defineConfig } from 'vite';
import {viteStaticCopy} from "vite-plugin-static-copy";
import * as path from "node:path";
import { normalizePath } from 'vite'

export default defineConfig({
    plugins: [
        viteStaticCopy({
            targets: [
                {
                    // Путь к файлу вне проекта (поднимитесь на уровень выше через ../)
                    src: [normalizePath(path.resolve(import.meta.dirname, '../../disks/xd0.dsk')), normalizePath(path.resolve(import.meta.dirname, '../../disks/xd1.dsk')), normalizePath(path.resolve(import.meta.dirname, '../../disks/xd2.dsk'))],
                    // Куда положить внутри сборки dist/ (например, dist/external/)
                    dest: 'assets'
                }
        ]})],
    publicDir: './public',
    assetsInclude: ['**/*.wasm'],
    base: '/kronos/',
    esbuild: {
        jsx: 'transform',
        // Говорим сборщику использовать фабрику Mithril (m) для JSX
        jsxFactory: 'm',
        jsxFragment: 'm.Fragment'
    }
});
