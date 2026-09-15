import { defineConfig } from 'vite';

export default defineConfig({
    esbuild: {
        jsx: 'transform',
        // Говорим сборщику использовать фабрику Mithril (m) для JSX
        jsxFactory: 'm',
        jsxFragment: 'm.Fragment'
    }
});
