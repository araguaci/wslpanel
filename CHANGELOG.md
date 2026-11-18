# Changelog

## Não publicado

### pt_BR

### en

### es

## 0.2.0 — 2026-11-18

### pt_BR

- Aba Processos, lida de `/proc`, com SIGTERM confirmado.
- Abas do kit, diálogo de confirmação e aviso ao terminar uma ação.
- Botão Copiar no comando `sudo` que o rodapé mostra.
- Tema Auto, Claro ou Escuro.
- Plano em [docs/PLANO.md](docs/PLANO.md).
- Aba Docker, só quando o cliente existe: CPU, memória, PIDs e estado dos containers.
- Aba Logs: final de `/var/log`, de 50 em 50 linhas.
- Screenshot da janela no README.
- Passo a passo de versão, changelog e release.

### en

- Processes tab, read from `/proc`, with a confirmed SIGTERM.
- Kit tabs, a confirmation dialog and a notice when an action finishes.
- Copy button for the `sudo` command the footer shows.
- Theme Auto, Light or Dark.
- Plan in [docs/PLANO.md](docs/PLANO.md).
- Docker tab, only when the client exists: container CPU, memory, PIDs and status.
- Logs tab: the end of `/var/log`, in steps of 50 lines.
- Window screenshot in the README.
- Version, changelog and release steps.

### es

- Pestaña Procesos, leída de `/proc`, con SIGTERM confirmado.
- Pestañas del kit, diálogo de confirmación y aviso al terminar una acción.
- Botón Copiar en el comando `sudo` que muestra el pie.
- Tema Auto, Claro u Oscuro.
- Plan en [docs/PLANO.md](docs/PLANO.md).
- Pestaña Docker, solo cuando el cliente existe: CPU, memoria, PIDs y estado de los contenedores.
- Pestaña Logs: el final de `/var/log`, de 50 en 50 líneas.
- Captura de la ventana en el README.
- Pasos de versión, changelog y release.

## 0.1.0 — 2026-11-18

Primeira release.

### pt_BR

- Página inicial com CPU, RAM, disco, `/tmp` e `/var/log`, barras e histórico no ritmo de um segundo.
- Limpar `/tmp` preserva os sockets da sessão (`.X11-unix`, `.ICE-unix`, `.XIM-unix`, `.font-unix`).
- Limpar logs remove só arquivos já rodados (`.gz`, `.xz`, `.bz2`, `.old` ou nome terminado em `.<número>`).
- Aba Programas: busca, filtros, ordenação, atualizações, órfãos e ações do apt com confirmação.
- Interface em português (pt_BR), inglês e espanhol. `WSLPANEL_LANG` ou os botões PT, EN e ES.
- Rodapé com a versão e a data desta release.

### en

- Home page with CPU, RAM, disk, `/tmp` and `/var/log`, bars and a one-second history.
- Clean `/tmp` keeps the session sockets (`.X11-unix`, `.ICE-unix`, `.XIM-unix`, `.font-unix`).
- Clean logs removes only rotated files (`.gz`, `.xz`, `.bz2`, `.old`, or a name ending in `.<digits>`).
- Programs tab: search, filters, sort, updates, orphans and confirmed apt actions.
- Interface in Portuguese (pt_BR), English and Spanish. `WSLPANEL_LANG` or the PT, EN and ES buttons.
- Footer shows this release's version and date.

### es

- Página inicial con CPU, RAM, disco, `/tmp` y `/var/log`, barras e historial a un segundo.
- Limpiar `/tmp` conserva los sockets de la sesión (`.X11-unix`, `.ICE-unix`, `.XIM-unix`, `.font-unix`).
- Limpiar logs borra solo archivos ya rotados (`.gz`, `.xz`, `.bz2`, `.old` o nombre terminado en `.<número>`).
- Pestaña Programas: búsqueda, filtros, orden, actualizaciones, huérfanos y acciones de apt con confirmación.
- Interfaz en portugués (pt_BR), inglés y español. `WSLPANEL_LANG` o los botones PT, EN y ES.
- El pie muestra la versión y la fecha de esta release.
