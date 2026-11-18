//! pt_BR, en and es. WSLPANEL_LANG wins, then LC_ALL, LC_MESSAGES and LANG.
//! An empty, C or POSIX locale stays on Portuguese.
const std = @import("std");

pub const Lang = enum { pt_BR, en, es };

pub const Id = enum {
    app_title,
    subtitle_resources,
    tab_resources,
    tab_processes,
    tab_programs,
    search,
    reload,
    indexes,
    upgrade_all,
    filter_programs,
    filter_manual,
    filter_all,
    filter_updates,
    filter_orphans,
    filter_libraries,
    sort_name,
    sort_size,
    sort_installed,
    load_failed,
    empty_filter,
    select_package,
    select_hint,
    fact_version,
    fact_update,
    fact_size,
    fact_origin,
    origin_auto,
    origin_manual,
    fact_installed,
    fact_section,
    fact_arch,
    fact_maintainer,
    fact_required,
    dependencies,
    confirm,
    cancel,
    upgrade,
    remove,
    clean_orphans,
    essential_blocked,
    required_blocked,
    badge_update,
    badge_orphan,
    pending_upgrade_all,
    pending_autoremove,
    pending_index,
    bad_name,
    apt_start_failed,
    sudo_password,
    done,
    footer_resources,
    footer_programs,
    cpu,
    ram,
    disk,
    tmp_hint,
    log_hint,
    clean_tmp,
    clean_logs,
    confirm_tmp,
    confirm_logs,
    open_failed,
    nothing_denied,
    subtitle_processes,
    footer_processes,
    theme_auto,
    theme_light,
    theme_dark,
    copy_cmd,
    copied,
    proc_search,
    proc_name,
    proc_state,
    proc_kill,
    proc_empty,
    proc_ended,
    proc_denied,
    tab_docker,
    tab_logs,
    subtitle_docker,
    subtitle_logs,
    footer_docker,
    footer_logs,
    docker_empty,
    docker_down,
    log_empty,
    log_binary,
    log_denied,
    log_file,
};

pub fn t(lang: Lang, id: Id) []const u8 {
    return switch (lang) {
        .pt_BR => pt(id),
        .en => en(id),
        .es => es(id),
    };
}

pub fn parse(v: []const u8) ?Lang {
    if (v.len == 0 or std.mem.eql(u8, v, "C") or std.mem.eql(u8, v, "POSIX")) return null;
    if (starts(v, "pt")) return .pt_BR;
    if (starts(v, "es")) return .es;
    if (starts(v, "en")) return .en;
    return null;
}

pub fn detect() Lang {
    const names = .{ "WSLPANEL_LANG", "LC_ALL", "LC_MESSAGES", "LANG" };
    inline for (names) |name| {
        if (std.c.getenv(name)) |p| if (parse(std.mem.span(p))) |lang| return lang;
    }
    return .pt_BR;
}

pub fn distroSub(a: std.mem.Allocator, lang: Lang, name: []const u8) []const u8 {
    return switch (lang) {
        .pt_BR => std.fmt.allocPrint(a, "{s} · pacotes desta distro, com origem, tamanho, atualização e órfãos", .{name}) catch "",
        .en => std.fmt.allocPrint(a, "{s} · packages in this distro, with origin, size, updates and orphans", .{name}) catch "",
        .es => std.fmt.allocPrint(a, "{s} · paquetes de esta distro, con origen, tamaño, actualización y huérfanos", .{name}) catch "",
    };
}

pub fn listStats(a: std.mem.Allocator, lang: Lang, n: usize, size: []const u8, updates: usize, orphans: usize) []const u8 {
    return switch (lang) {
        .pt_BR => std.fmt.allocPrint(a, "{d} nesta lista · {s} · {d} atualizações · {d} órfãos", .{ n, size, updates, orphans }) catch "",
        .en => std.fmt.allocPrint(a, "{d} in this list · {s} · {d} updates · {d} orphans", .{ n, size, updates, orphans }) catch "",
        .es => std.fmt.allocPrint(a, "{d} en esta lista · {s} · {d} actualizaciones · {d} huérfanos", .{ n, size, updates, orphans }) catch "",
    };
}

pub fn requiredCount(a: std.mem.Allocator, lang: Lang, n: usize) []const u8 {
    return switch (lang) {
        .pt_BR => std.fmt.allocPrint(a, "{d} pacotes", .{n}) catch "",
        .en => std.fmt.allocPrint(a, "{d} packages", .{n}) catch "",
        .es => std.fmt.allocPrint(a, "{d} paquetes", .{n}) catch "",
    };
}

pub fn pendingRemove(a: std.mem.Allocator, lang: Lang, name: []const u8) []const u8 {
    return switch (lang) {
        .pt_BR => std.fmt.allocPrint(a, "Remover {s}? O que depender dele pode quebrar.", .{name}) catch "",
        .en => std.fmt.allocPrint(a, "Remove {s}? Anything that depends on it may break.", .{name}) catch "",
        .es => std.fmt.allocPrint(a, "¿Quitar {s}? Lo que dependa de él puede fallar.", .{name}) catch "",
    };
}

pub fn pendingPurge(a: std.mem.Allocator, lang: Lang, name: []const u8) []const u8 {
    return switch (lang) {
        .pt_BR => std.fmt.allocPrint(a, "Remover {s} e a configuração que ele deixou?", .{name}) catch "",
        .en => std.fmt.allocPrint(a, "Remove {s} and the configuration it left behind?", .{name}) catch "",
        .es => std.fmt.allocPrint(a, "¿Quitar {s} y la configuración que dejó?", .{name}) catch "",
    };
}

pub fn procCount(a: std.mem.Allocator, lang: Lang, n: usize) []const u8 {
    return switch (lang) {
        .pt_BR => std.fmt.allocPrint(a, "{d} processos", .{n}) catch "",
        .en => std.fmt.allocPrint(a, "{d} processes", .{n}) catch "",
        .es => std.fmt.allocPrint(a, "{d} procesos", .{n}) catch "",
    };
}

pub fn dockerCount(a: std.mem.Allocator, lang: Lang, n: usize) []const u8 {
    return switch (lang) {
        .pt_BR => std.fmt.allocPrint(a, "{d} containers", .{n}) catch "",
        .en => std.fmt.allocPrint(a, "{d} containers", .{n}) catch "",
        .es => std.fmt.allocPrint(a, "{d} contenedores", .{n}) catch "",
    };
}

pub fn logCount(a: std.mem.Allocator, lang: Lang, n: usize) []const u8 {
    return switch (lang) {
        .pt_BR => std.fmt.allocPrint(a, "{d} linhas", .{n}) catch "",
        .en => std.fmt.allocPrint(a, "{d} lines", .{n}) catch "",
        .es => std.fmt.allocPrint(a, "{d} líneas", .{n}) catch "",
    };
}

pub fn pendingKill(a: std.mem.Allocator, lang: Lang, name: []const u8, pid: u32) []const u8 {
    return switch (lang) {
        .pt_BR => std.fmt.allocPrint(a, "Encerrar {s} ({d})? Ele recebe SIGTERM.", .{ name, pid }) catch "",
        .en => std.fmt.allocPrint(a, "End {s} ({d})? It is sent SIGTERM.", .{ name, pid }) catch "",
        .es => std.fmt.allocPrint(a, "¿Terminar {s} ({d})? Recibe SIGTERM.", .{ name, pid }) catch "",
    };
}

pub fn pendingUpgrade(a: std.mem.Allocator, lang: Lang, name: []const u8) []const u8 {
    return switch (lang) {
        .pt_BR => std.fmt.allocPrint(a, "Instalar a versão nova de {s}?", .{name}) catch "",
        .en => std.fmt.allocPrint(a, "Install the new version of {s}?", .{name}) catch "",
        .es => std.fmt.allocPrint(a, "¿Instalar la versión nueva de {s}?", .{name}) catch "",
    };
}

pub fn loadCores(a: std.mem.Allocator, lang: Lang, load: f32, n: usize) []const u8 {
    return switch (lang) {
        .pt_BR => std.fmt.allocPrint(a, "carga {d:.2} · {d} núcleos", .{ load, n }) catch "",
        .en => std.fmt.allocPrint(a, "load {d:.2} · {d} cores", .{ load, n }) catch "",
        .es => std.fmt.allocPrint(a, "carga {d:.2} · {d} núcleos", .{ load, n }) catch "",
    };
}

pub fn ofTotal(a: std.mem.Allocator, lang: Lang, used: []const u8, total: []const u8) []const u8 {
    return switch (lang) {
        .pt_BR => std.fmt.allocPrint(a, "{s} de {s}", .{ used, total }) catch "",
        .en => std.fmt.allocPrint(a, "{s} of {s}", .{ used, total }) catch "",
        .es => std.fmt.allocPrint(a, "{s} de {s}", .{ used, total }) catch "",
    };
}

pub fn swapOf(a: std.mem.Allocator, lang: Lang, used: []const u8, total: []const u8) []const u8 {
    return switch (lang) {
        .pt_BR => std.fmt.allocPrint(a, "swap {s} de {s}", .{ used, total }) catch "",
        .en => std.fmt.allocPrint(a, "swap {s} of {s}", .{ used, total }) catch "",
        .es => std.fmt.allocPrint(a, "swap {s} de {s}", .{ used, total }) catch "",
    };
}

pub fn diskLine(a: std.mem.Allocator, lang: Lang, used: []const u8, total: []const u8) []const u8 {
    return switch (lang) {
        .pt_BR => std.fmt.allocPrint(a, "/ · {s} de {s}", .{ used, total }) catch "",
        .en => std.fmt.allocPrint(a, "/ · {s} of {s}", .{ used, total }) catch "",
        .es => std.fmt.allocPrint(a, "/ · {s} de {s}", .{ used, total }) catch "",
    };
}

pub fn cleaned(buf: []u8, lang: Lang, n: usize) []const u8 {
    return switch (lang) {
        .pt_BR => std.fmt.bufPrint(buf, "Liberados {d} arquivos.", .{n}) catch "Limpeza concluída.",
        .en => std.fmt.bufPrint(buf, "Freed {d} files.", .{n}) catch "Clean finished.",
        .es => std.fmt.bufPrint(buf, "Liberados {d} archivos.", .{n}) catch "Limpieza hecha.",
    };
}

pub fn partialClean(buf: []u8, lang: Lang, n: usize) []const u8 {
    return switch (lang) {
        .pt_BR => std.fmt.bufPrint(buf, "Liberados {d} arquivos. Alguns ficaram sem permissão.", .{n}) catch "Limpeza parcial.",
        .en => std.fmt.bufPrint(buf, "Freed {d} files. Some were left without permission.", .{n}) catch "Partial clean.",
        .es => std.fmt.bufPrint(buf, "Liberados {d} archivos. Algunos quedaron sin permiso.", .{n}) catch "Limpieza parcial.",
    };
}

fn starts(s: []const u8, p: []const u8) bool {
    if (s.len < p.len) return false;
    for (p, s[0..p.len]) |a, b| if (std.ascii.toLower(a) != std.ascii.toLower(b)) return false;
    return true;
}

fn pt(id: Id) []const u8 {
    return switch (id) {
        .app_title => "Painel do WSL",
        .subtitle_resources => "CPU, memória, disco, /tmp e logs, no ritmo de um segundo",
        .tab_resources => "Recursos",
        .tab_processes => "Processos",
        .tab_programs => "Programas",
        .search => "Buscar pacotes",
        .reload => "Recarregar",
        .indexes => "Índices",
        .upgrade_all => "Atualizar todos",
        .filter_programs => "Programas",
        .filter_manual => "Manuais",
        .filter_all => "Todos",
        .filter_updates => "Atualizações",
        .filter_orphans => "Órfãos",
        .filter_libraries => "Bibliotecas",
        .sort_name => "Nome",
        .sort_size => "Tamanho",
        .sort_installed => "Instalado",
        .load_failed => "Não foi possível ler os pacotes",
        .empty_filter => "Nenhum pacote neste filtro",
        .select_package => "Selecione um pacote",
        .select_hint => "A lista mostra o que está instalado nesta distro. Programas esconde bibliotecas e o que entrou só como dependência.",
        .fact_version => "Versão",
        .fact_update => "Atualização",
        .fact_size => "Tamanho",
        .fact_origin => "Origem",
        .origin_auto => "dependência automática",
        .origin_manual => "instalação manual",
        .fact_installed => "Instalado em",
        .fact_section => "Seção",
        .fact_arch => "Arquitetura",
        .fact_maintainer => "Responsável",
        .fact_required => "Exigido por",
        .dependencies => "Dependências",
        .confirm => "Confirmar",
        .cancel => "Cancelar",
        .upgrade => "Atualizar",
        .remove => "Remover",
        .clean_orphans => "Limpar órfãos",
        .essential_blocked => "Pacote essencial: a remoção fica bloqueada.",
        .required_blocked => "Prioridade obrigatória: a remoção fica bloqueada.",
        .badge_update => "atualizar",
        .badge_orphan => "órfão",
        .pending_upgrade_all => "Atualizar todos os pacotes com versão nova nos índices?",
        .pending_autoremove => "Remover dependências automáticas que ninguém mais exige?",
        .pending_index => "Baixar de novo os índices do apt?",
        .bad_name => "nome de pacote recusado",
        .apt_start_failed => "não foi possível iniciar o apt",
        .sudo_password => "rode no terminal; sudo pede a senha",
        .done => "Concluído.",
        .footer_resources => "A limpeza de /tmp preserva os sockets da sessão. Em /var/log só saem os arquivos já rodados.",
        .footer_programs => "Remover e atualizar pedem sudo. Sem senha guardada, o comando aparece aqui para o terminal.",
        .cpu => "CPU",
        .ram => "RAM",
        .disk => "Disco",
        .tmp_hint => "Sockets da sessão gráfica ficam.",
        .log_hint => "Só os arquivos já rodados (.gz, .1, .old).",
        .clean_tmp => "Limpar /tmp",
        .clean_logs => "Limpar logs",
        .confirm_tmp => "Apagar o conteúdo de /tmp?",
        .confirm_logs => "Apagar o rodízio de /var/log?",
        .open_failed => "Não foi possível abrir a pasta.",
        .nothing_denied => "Nada apagado: sem permissão para estes arquivos.",
        .subtitle_processes => "Processos desta distro, por CPU e memória",
        .footer_processes => "Encerrar envia SIGTERM. O processo 1 e este painel ficam de fora.",
        .theme_auto => "Auto",
        .theme_light => "Claro",
        .theme_dark => "Escuro",
        .copy_cmd => "Copiar",
        .copied => "Comando copiado.",
        .proc_search => "Buscar processos",
        .proc_name => "Nome",
        .proc_state => "Estado",
        .proc_kill => "Encerrar",
        .proc_empty => "Nenhum processo neste filtro",
        .proc_ended => "Sinal enviado.",
        .proc_denied => "Não foi possível encerrar.",
        .tab_docker => "Docker",
        .tab_logs => "Logs",
        .subtitle_docker => "CPU, memória e processos de cada container",
        .subtitle_logs => "O final dos arquivos de texto em /var/log",
        .footer_docker => "CPU e memória vêm do cgroup. A aba só aparece quando o docker está instalado.",
        .footer_logs => "O painel mostra o fim do arquivo. Cada passo soma 50 linhas.",
        .docker_empty => "Nenhum container em execução",
        .docker_down => "O Docker não respondeu.",
        .log_empty => "Nenhum log de texto legível em /var/log",
        .log_binary => "Arquivo binário: o painel não mostra estes bytes.",
        .log_denied => "Não foi possível ler este arquivo.",
        .log_file => "Arquivo",
    };
}

fn en(id: Id) []const u8 {
    return switch (id) {
        .app_title => "WSL Panel",
        .subtitle_resources => "CPU, memory, disk, /tmp and logs, once a second",
        .tab_resources => "Resources",
        .tab_processes => "Processes",
        .tab_programs => "Programs",
        .search => "Search packages",
        .reload => "Reload",
        .indexes => "Indexes",
        .upgrade_all => "Upgrade all",
        .filter_programs => "Programs",
        .filter_manual => "Manual",
        .filter_all => "All",
        .filter_updates => "Updates",
        .filter_orphans => "Orphans",
        .filter_libraries => "Libraries",
        .sort_name => "Name",
        .sort_size => "Size",
        .sort_installed => "Installed",
        .load_failed => "Could not read the packages",
        .empty_filter => "No package in this filter",
        .select_package => "Select a package",
        .select_hint => "The list shows what is installed in this distro. Programs hides libraries and packages that arrived only as dependencies.",
        .fact_version => "Version",
        .fact_update => "Update",
        .fact_size => "Size",
        .fact_origin => "Origin",
        .origin_auto => "automatic dependency",
        .origin_manual => "manual install",
        .fact_installed => "Installed on",
        .fact_section => "Section",
        .fact_arch => "Architecture",
        .fact_maintainer => "Maintainer",
        .fact_required => "Required by",
        .dependencies => "Dependencies",
        .confirm => "Confirm",
        .cancel => "Cancel",
        .upgrade => "Upgrade",
        .remove => "Remove",
        .clean_orphans => "Clean orphans",
        .essential_blocked => "Essential package: removal is blocked.",
        .required_blocked => "Required priority: removal is blocked.",
        .badge_update => "update",
        .badge_orphan => "orphan",
        .pending_upgrade_all => "Upgrade every package that has a newer version in the indexes?",
        .pending_autoremove => "Remove automatic dependencies that nothing requires anymore?",
        .pending_index => "Download the apt indexes again?",
        .bad_name => "package name refused",
        .apt_start_failed => "could not start apt",
        .sudo_password => "run it in a terminal; sudo asks for the password",
        .done => "Done.",
        .footer_resources => "Cleaning /tmp keeps the session sockets. In /var/log only rotated files are removed.",
        .footer_programs => "Remove and upgrade need sudo. With no stored password, the command is shown here for the terminal.",
        .cpu => "CPU",
        .ram => "RAM",
        .disk => "Disk",
        .tmp_hint => "Graphical session sockets stay.",
        .log_hint => "Only rotated files (.gz, .1, .old).",
        .clean_tmp => "Clean /tmp",
        .clean_logs => "Clean logs",
        .confirm_tmp => "Delete the contents of /tmp?",
        .confirm_logs => "Delete rotated files in /var/log?",
        .open_failed => "Could not open the folder.",
        .nothing_denied => "Nothing deleted: no permission for these files.",
        .subtitle_processes => "Processes in this distro, by CPU and memory",
        .footer_processes => "End sends SIGTERM. Process 1 and this panel stay.",
        .theme_auto => "Auto",
        .theme_light => "Light",
        .theme_dark => "Dark",
        .copy_cmd => "Copy",
        .copied => "Command copied.",
        .proc_search => "Search processes",
        .proc_name => "Name",
        .proc_state => "State",
        .proc_kill => "End",
        .proc_empty => "No process in this filter",
        .proc_ended => "Signal sent.",
        .proc_denied => "Could not end it.",
        .tab_docker => "Docker",
        .tab_logs => "Logs",
        .subtitle_docker => "CPU, memory and processes of each container",
        .subtitle_logs => "The end of the text files in /var/log",
        .footer_docker => "CPU and memory come from the cgroup. This tab appears only when docker is installed.",
        .footer_logs => "The panel shows the end of the file. Each step adds 50 lines.",
        .docker_empty => "No running container",
        .docker_down => "Docker did not answer.",
        .log_empty => "No readable text log in /var/log",
        .log_binary => "Binary file: the panel does not show these bytes.",
        .log_denied => "Could not read this file.",
        .log_file => "File",
    };
}

fn es(id: Id) []const u8 {
    return switch (id) {
        .app_title => "Panel de WSL",
        .subtitle_resources => "CPU, memoria, disco, /tmp y logs, una vez por segundo",
        .tab_resources => "Recursos",
        .tab_processes => "Procesos",
        .tab_programs => "Programas",
        .search => "Buscar paquetes",
        .reload => "Recargar",
        .indexes => "Índices",
        .upgrade_all => "Actualizar todos",
        .filter_programs => "Programas",
        .filter_manual => "Manuales",
        .filter_all => "Todos",
        .filter_updates => "Actualizaciones",
        .filter_orphans => "Huérfanos",
        .filter_libraries => "Bibliotecas",
        .sort_name => "Nombre",
        .sort_size => "Tamaño",
        .sort_installed => "Instalado",
        .load_failed => "No se pudieron leer los paquetes",
        .empty_filter => "Ningún paquete en este filtro",
        .select_package => "Seleccione un paquete",
        .select_hint => "La lista muestra lo instalado en esta distro. Programas oculta bibliotecas y lo que entró solo como dependencia.",
        .fact_version => "Versión",
        .fact_update => "Actualización",
        .fact_size => "Tamaño",
        .fact_origin => "Origen",
        .origin_auto => "dependencia automática",
        .origin_manual => "instalación manual",
        .fact_installed => "Instalado el",
        .fact_section => "Sección",
        .fact_arch => "Arquitectura",
        .fact_maintainer => "Responsable",
        .fact_required => "Exigido por",
        .dependencies => "Dependencias",
        .confirm => "Confirmar",
        .cancel => "Cancelar",
        .upgrade => "Actualizar",
        .remove => "Quitar",
        .clean_orphans => "Limpiar huérfanos",
        .essential_blocked => "Paquete esencial: la eliminación queda bloqueada.",
        .required_blocked => "Prioridad obligatoria: la eliminación queda bloqueada.",
        .badge_update => "actualizar",
        .badge_orphan => "huérfano",
        .pending_upgrade_all => "¿Actualizar todos los paquetes con versión nueva en los índices?",
        .pending_autoremove => "¿Quitar dependencias automáticas que ya nadie exige?",
        .pending_index => "¿Descargar de nuevo los índices de apt?",
        .bad_name => "nombre de paquete rechazado",
        .apt_start_failed => "no se pudo iniciar apt",
        .sudo_password => "ejecútelo en la terminal; sudo pide la contraseña",
        .done => "Hecho.",
        .footer_resources => "La limpieza de /tmp conserva los sockets de la sesión. En /var/log solo salen los archivos ya rotados.",
        .footer_programs => "Quitar y actualizar piden sudo. Sin contraseña guardada, el comando aparece aquí para la terminal.",
        .cpu => "CPU",
        .ram => "RAM",
        .disk => "Disco",
        .tmp_hint => "Los sockets de la sesión gráfica se quedan.",
        .log_hint => "Solo los archivos ya rotados (.gz, .1, .old).",
        .clean_tmp => "Limpiar /tmp",
        .clean_logs => "Limpiar logs",
        .confirm_tmp => "¿Borrar el contenido de /tmp?",
        .confirm_logs => "¿Borrar la rotación de /var/log?",
        .open_failed => "No se pudo abrir la carpeta.",
        .nothing_denied => "Nada borrado: sin permiso para estos archivos.",
        .subtitle_processes => "Procesos de esta distro, por CPU y memoria",
        .footer_processes => "Terminar envía SIGTERM. El proceso 1 y este panel se quedan.",
        .theme_auto => "Auto",
        .theme_light => "Claro",
        .theme_dark => "Oscuro",
        .copy_cmd => "Copiar",
        .copied => "Comando copiado.",
        .proc_search => "Buscar procesos",
        .proc_name => "Nombre",
        .proc_state => "Estado",
        .proc_kill => "Terminar",
        .proc_empty => "Ningún proceso en este filtro",
        .proc_ended => "Señal enviada.",
        .proc_denied => "No se pudo terminar.",
        .tab_docker => "Docker",
        .tab_logs => "Logs",
        .subtitle_docker => "CPU, memoria y procesos de cada contenedor",
        .subtitle_logs => "El final de los archivos de texto en /var/log",
        .footer_docker => "CPU y memoria vienen del cgroup. La pestaña solo aparece cuando docker está instalado.",
        .footer_logs => "El panel muestra el final del archivo. Cada paso suma 50 líneas.",
        .docker_empty => "Ningún contenedor en ejecución",
        .docker_down => "Docker no respondió.",
        .log_empty => "Ningún log de texto legible en /var/log",
        .log_binary => "Archivo binario: el panel no muestra estos bytes.",
        .log_denied => "No se pudo leer este archivo.",
        .log_file => "Archivo",
    };
}
