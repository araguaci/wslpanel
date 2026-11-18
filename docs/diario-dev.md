# Diário de desenvolvimento

Aprendizados da 0.1.0, da 0.2.0 e das correções de instalação no `labmini` (2026-11-18). O que falta fazer está no [PLANO.md](PLANO.md). Publicar segue o [RELEASE.md](RELEASE.md).

## Ler `/proc` e o cgroup

Arquivo em `/proc` informa tamanho 0. `readFileAlloc` devolve vazio e o medidor fica em zero. A leitura que funciona é `openFile` e `readPositional` num buffer fixo.

A primeira amostra de CPU é 0%. O percentual é o delta entre duas leituras, cerca de um segundo depois. Em `/proc/stat`, o ocupado é o total menos idle e iowait. No container, `cpu.stat` guarda `usage_usec` (microssegundos de um núcleo). A página chama `frameIn(1)` enquanto está aberta. `--nanoui-wait` corre antes de `--nanoui-script`: um clique depois da espera ainda é a primeira amostra.

`std.posix.getpid` não existe no Zig 0.17. O pid vem de `std.os.linux.getpid`. `std.posix.kill` existe.

## Texto que o quadro guarda

`ui.text` fica com o ponteiro até o layout, depois que a função de view já voltou. Um `Proc` copiado para a pilha, com o nome num `[16]u8`, entrega um ponteiro morto. O desenho vira um bloco preto por letra, no tamanho do nome. O ponteiro tem de apontar para o item dentro da lista.

O nome de pacote escapa disso porque é uma fatia da arena: copiar o pacote copia o ponteiro, que continua válido. O mesmo vale para o caminho do log e para a linha do tail: a fatia aponta para o buffer do estado, não para uma cópia na pilha.

Numa linha, o `grow` fica na célula do nome. PID, CPU, RSS e estado têm largura fixa. Um espaçador com `grow` depois do nome come a largura, e o ellipsis reduz o texto a `...`.

`hasText` compara o nó inteiro. O rodapé é `wslpanel 0.2.0 · 2026-11-18`, então a versão entra com `containsText`. `clickText` acerta o primeiro nó igual. O botão `200` precisa nascer antes de uma linha de log que também seja `200`.

A lista virtual só constrói as linhas visíveis. O teste pede o nome da primeira linha ordenada, a que está na tela.

## Docker e logs

`docker stats --no-stream` trava cerca de 2,6 s. `docker ps` responde em dezenas de milissegundos. CPU, memória e PIDs vêm do cgroup: `system.slice/docker-<id>.scope` e, se esse não tiver `cpu.stat`, `/sys/fs/cgroup/docker/<id>`. Ler as duas árvores na mesma amostra zera o delta: a segunda vê o contador que a primeira acabou de gravar. Um `fresh` marca a linha já medida.

O id curto do `docker ps` é o prefixo do id de 64 hex do scope. Container novo, com `seen` falso, mostra 0% naquela amostra e passa a contar no segundo seguinte.

A aba existe quando o binário `docker` está no disco. O daemon caído mostra “não respondeu”, sem a aba sumir no meio do teste.

O tail lê no máximo 256 KB do fim. Se a leitura não começa no byte 0, a primeira linha está cortada e sai fora. Arquivo vazio não é a seleção inicial. Ficam de fora `.gz`, `.xz`, `.bz2`, `.zst` e os binários `wtmp`, `btmp`, `lastlog` e `faillog`.

## Compilar e abrir

Em `/mnt` (disco do Windows, 9p) o Zig não consegue renomear `.zig-cache` e a compilação para com `AccessDenied`. O cache local vai para o sistema de arquivos do Linux:

```sh
export ZIG_LOCAL_CACHE_DIR="$HOME/.cache/wslpanel-zig"
```

O binário em `zig-out` no `/mnt` grava normalmente. O que falha é o rename do cache.

`$HOME/.local` tem de existir antes de `tar -C`. Como root, o home é `/root` e essa pasta costuma não estar lá. `mkdir -p "$HOME/.local"` resolve. O `export PATH` vale só naquele terminal.

Sem GPU, o `GtkGLArea` pede OpenGL e a janela fecha. O log mostra `libEGL` com `fd -1`, `ZINK: failed to choose pdev` e o aviso do GDK de contexto abaixo de 3.2 (a área pede 3.0). Não há fallback silencioso para a CPU. O caminho é:

```sh
NANOUI_RENDERER=cpu ./zig-out/bin/wslpanel
```

Continua fazendo falta uma tela, com `DISPLAY` definido.

## Publicar

Não há workflow de release. A tag nasce no commit da `main` depois do merge. O binário é `ReleaseSafe`, sem extensão: `wslpanel-0.2.0-linux-x86_64`. As notas são a seção daquela versão no changelog, nas três línguas. A 0.1.0 e a 0.2.0 saíram no mesmo dia, então as duas levam a data 2026-11-18.

O snapshot headless não abre janela. A área de transferência do `Tester` não é a do sistema.

## Zig 0.17 neste app

`zig fetch --save` gravou `.path` no `build.zig.zon`. O pin que compila é `.url` mais o hash.

Dentro de um braço de `switch`, um `if` não é lado esquerdo de atribuição. O braço vira um bloco. `_ = parametro` é erro quando esse parâmetro também é usado.

`c.print` exige formato conhecido em tempo de compilação. Frase que muda com o idioma sai de `std.fmt.allocPrint`, com um literal por língua.
