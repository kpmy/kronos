# Эмулятор КРОНОС
Вариант эмулятора для NodeJS/Web/WASM. Инструкции портированы на WASM, диспетчеризация и некоторые мета-инструкции (push, pop, и т.д.) реализованы также в JS-обвязке. IO-периферия на JS.

## Запуск

```shell
yarn

node ./index.js
```
Логин под юзером `su`.

Местоположение дисков прописано в `.env` относительно данной папки.

```text
../../disks/xd0.dsk,../../disks/xd1.dsk
```
## TODO

Перечень нереализованных инструкций:
 - [ ] LEA
 - [ ] IOR
 - [ ] ARRCMP
 - [ ] WM
 - [ ] BM
 - [ ] FADD
 - [ ] FSUB
 - [ ] FMUL
 - [ ] FDIV
 - [ ] FCMP
 - [ ] FABS
 - [ ] FNEG
 - [ ] FFCT
 - [ ] FOR1
 - [ ] FOR2
 - [ ] ENTC
 - [ ] NOP
 - [ ] QUOT
 - [ ] BBU
 - [ ] BBP
 - [ ] BBLT
 - [ ] CM
 - [ ] CHKBX
 - [ ] BMG
 - [ ] USR
 - [ ] DOT
 - [ ] INVLD

Файловая система пока read-only.
