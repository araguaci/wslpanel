# Versão, changelog e release

O número publicado é o de `build.zig.zon`. O rodapé mostra esse número e a data de `src/meta.zig`. O histórico fica no [CHANGELOG.md](../CHANGELOG.md). A `main` no GitHub é a 0.1.0. O repositório não tem workflow de release: a tag e o binário sobem depois que o pull request entra na `main`.

A 0.1.0 está em <https://github.com/araguaci/wslpanel/releases/tag/v0.1.0>, com o arquivo `wslpanel-0.1.0-linux-x86_64`.

## 1. Anotar enquanto a branch anda

Cada mudança que a pessoa vê entra no topo do changelog, na seção `## Não publicado`, nas três línguas, nesta ordem: `pt_BR`, `en`, `es`.

```md
## Não publicado

### pt_BR

- O que mudou, numa frase.

### en

- What changed, in one sentence.

### es

- Qué cambió, en una frase.
```

A versão em `build.zig.zon` continua a da última release até o passo 3.

## 2. Escolher o número

O formato é `major.minor.patch`.

| Mudança | Exemplo a partir da 0.1.0 |
| --- | --- |
| Correção da versão atual | 0.1.1 |
| Recurso novo | 0.2.0 |
| Quebra do que já estava publicado | 1.0.0 |

Processos, Docker, logs e tema, hoje na `dev`, são recurso novo: a próxima release dessa linha é a **0.2.0**. Uma correção só da 0.1.0, sem esses recursos, seria a 0.1.1.

A data é o dia da release, `YYYY-MM-DD`.

## 3. Versionar

Numa branch a partir da `dev` (ou na própria `dev`, se ela for o PR):

1. Em `build.zig.zon`, trocar `.version = "0.1.0"` pelo número novo.
2. Em `src/meta.zig`, gravar a data: `pub const date = "2026-11-18";`.
3. Nos três README, a primeira frase cita a versão e a data:
   - `README.md`: `A versão **0.2.0** (2026-11-18)`
   - `README-EN.md`: `Version **0.2.0** (2026-11-18)`
   - `README-ES.md`: `La versión **0.2.0** (2026-11-18)`
4. No changelog, o bloco `## Não publicado` vira o título da release. Em seguida abre-se um bloco vazio para o que vier depois.

```md
## Não publicado

### pt_BR

### en

### es

## 0.2.0 — 2026-11-18

### pt_BR

- …
```

O corpo da release no GitHub é só a seção dessa versão, da linha `## 0.2.0` até antes de `## Não publicado`. As três línguas vão juntas, como na 0.1.0.

## 4. Provar o binário

Os testes leem a versão e a data no rodapé.

```sh
zig build test
```

O binário da release é `ReleaseSafe`, para Linux x86_64. Se a árvore está em `/mnt` (o disco do Windows no WSL), o cache do Zig fica no sistema de arquivos do Linux. Sem isso, o build para com `AccessDenied` ao renomear `.zig-cache`.

```sh
export ZIG_LOCAL_CACHE_DIR="$HOME/.cache/wslpanel-zig"
zig build -Doptimize=ReleaseSafe
cp -f zig-out/bin/wslpanel "wslpanel-0.2.0-linux-x86_64"
```

Num diretório do próprio Linux (`~`), o `export` não entra. A conferência da janela é sem mostrá-la:

```sh
./zig-out/bin/wslpanel --nanoui-snapshot=/tmp/wslpanel.png --nanoui-wait=2
```

O arquivo publicado não leva extensão. O da 0.1.0 tem esse nome e cerca de 9,8 MB.

## 5. Abrir o pull request

O PR sai da branch de trabalho para a `main`. A tag ainda não existe.

```sh
git push -u origin HEAD
gh pr create --base main --head dev --title "Publicar a 0.2.0" --body "$(cat <<'EOF'
## Summary
- Versão 0.2.0, data no rodapé e changelog em pt_BR, en e es.
- O que a release entrega, em uma ou duas frases.

## Test plan
- [ ] `zig build test`
- [ ] `zig build -Doptimize=ReleaseSafe` gera `zig-out/bin/wslpanel`
- [ ] O rodapé mostra a versão e a data novas
- [ ] O changelog não tem mais esses itens em "Não publicado"

EOF
)"
```

O merge é o commit que recebe a tag. Com o PR aberto, o número e o changelog ainda podem ser ajustados no mesmo branch.

## 6. Tag e release

Depois do merge, na `main` atualizada:

```sh
git checkout main
git pull origin main
git tag -a v0.2.0 -m "wslpanel 0.2.0"
git push origin v0.2.0
```

As notas são a seção `## 0.2.0` do changelog, gravada num arquivo (por exemplo `/tmp/wslpanel-0.2.0-notes.md`). O binário é o que o passo 4 gerou nesse mesmo commit.

```sh
gh release create v0.2.0 wslpanel-0.2.0-linux-x86_64 \
  --repo araguaci/wslpanel \
  --target main \
  --title "wslpanel 0.2.0" \
  --notes-file /tmp/wslpanel-0.2.0-notes.md
```

Conferir a página <https://github.com/araguaci/wslpanel/releases/tag/v0.2.0>: título `wslpanel 0.2.0`, as três línguas e o arquivo `wslpanel-0.2.0-linux-x86_64` para download.

## Lista

- [ ] Itens novos no `## Não publicado`, em pt_BR, en e es
- [ ] Número em `build.zig.zon` e data em `src/meta.zig`
- [ ] Versão e data nos três README
- [ ] Seção do changelog renomeada para `## x.y.z — YYYY-MM-DD`
- [ ] `zig build test` e o binário `ReleaseSafe`
- [ ] Pull request para a `main`
- [ ] Tag `vx.y.z` no commit do merge, e a release com o binário
