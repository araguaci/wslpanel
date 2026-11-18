# Plano do wslpanel

A ordem segue o que os exemplos e os apps do nanoui já desenham. O que está marcado entrou na árvore de trabalho depois da 0.1.0. Publicar uma versão segue [RELEASE.md](RELEASE.md).

## Feito na 0.1.0

- Página Recursos: CPU, carga, núcleos, RAM, swap, disco, `/tmp`, `/var/log` e o histórico de um segundo.
- Limpar `/tmp` preserva os sockets da sessão. Limpar logs só apaga arquivo já rodado.
- Aba Programas: busca, filtros, ordenação, atualizações, órfãos e apt com sudo, sem guardar senha.
- Português, inglês e espanhol. Rodapé com versão e data.

## Primeiras melhorias

Estas quatro já estão no código.

- [x] **Processos.** Lista virtual, como a página List da galeria, lendo `/proc`: nome, PID, fatia de CPU, RSS e estado. Encerrar pede confirmação e envia SIGTERM. O processo 1 e este painel ficam de fora.
- [x] **Abas, diálogo e aviso.** As páginas usam as abas do `nanoui.kit`. Limpar, apt e encerrar abrem um diálogo. O resultado aparece num aviso, o toast do kit.
- [x] **Copiar o comando sudo.** Quando o apt pede senha, o rodapé mostra o comando e o botão Copiar. Nos testes a cópia fica na área de transferência do Tester, sem tocar a do sistema.
- [x] **Tema.** Auto, Claro ou Escuro, como a galeria: Auto deixa `theme_chosen` vazio e o painel segue o sistema.
- [x] **Docker.** A aba só entra se o cliente `docker` existir. CPU e memória vêm do cgroup; o nome e o estado, de `docker ps`.
- [x] **Logs.** O fim dos arquivos de texto em `/var/log`, com 50, 100, 150, 200… linhas, de 50 em 50, até 2000.

## Próximo

- [ ] **Lembrar escolhas.** O exemplo basics guarda um valor entre aberturas. Guardar idioma, aba, ordenação e tema.
- [ ] **Soltar um `.deb`.** O exemplo drop lê os arquivos soltos na janela. Soltar um pacote prepara `apt install`.
- [ ] **Abrir a pasta.** `desktop.openPath` abre `/var/log` ou os arquivos de um pacote no gerenciador.
- [ ] **Bandeja.** O ícone Linux (`StatusNotifierItem`) mostra CPU e RAM, com menu para abrir o painel ou limpar.
- [ ] **Linha do tempo.** O kit tem a linha do tempo, e o nanocua registra o que a sessão fez. Uma lista do que este painel limpou e do apt que rodou.
- [ ] **Atualizar o próprio app.** `update.zig` procura uma release nova no GitHub.

## Depois

- [ ] **Janela estreita.** O exemplo duo e a galeria no telefone empilham lista e detalhe. Hoje o detalhe de um pacote fica em 340 px.
- [ ] **Nomes para o leitor de tela.** O exemplo access marca o que o VoiceOver lê. Os medidores e os botões de limpar entram nessa leitura.
- [ ] **Anéis de CPU e RAM.** O todo desenha anéis de progresso. Os cartões podem usar o mesmo, junto das barras.
- [ ] **Selos** em “atualizar” e “órfão”, e um esqueleto enquanto o dpkg é lido. Os dois estão na página Kit da galeria.
