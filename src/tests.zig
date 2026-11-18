//! The catalog's reading of dpkg, and the view driven offscreen.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const app_view = @import("app.zig");
const catalog = @import("catalog.zig");
const i18n = @import("i18n.zig");
const meta = @import("meta.zig");
const resources = @import("resources.zig");

const status =
    \\Package: curl
    \\Status: install ok installed
    \\Priority: optional
    \\Section: web
    \\Installed-Size: 397
    \\Maintainer: Curl Maintainers <curl@example>
    \\Architecture: amd64
    \\Version: 8.4.0
    \\Depends: libc6 (>= 2.34)
    \\Description: Transferir URLs
    \\ A longer line that is not the summary.
    \\
    \\Package: libfoo
    \\Status: install ok installed
    \\Priority: optional
    \\Section: libs
    \\Installed-Size: 80
    \\Architecture: amd64
    \\Version: 1.0
    \\Provides: libfoo-virtual
    \\Description: Biblioteca foo
    \\
    \\Package: libc6
    \\Status: install ok installed
    \\Priority: required
    \\Section: libs
    \\Essential: yes
    \\Installed-Size: 12000
    \\Architecture: amd64
    \\Version: 2.36-9
    \\Description: Biblioteca C
    \\
    \\Package: gone
    \\Status: deinstall ok config-files
    \\Version: 0.1
    \\Description: ja removido
    \\
;

const extended =
    \\Package: libfoo
    \\Architecture: amd64
    \\Auto-Installed: 1
    \\
;

test "debian versions put the greater release last" {
    try std.testing.expect(catalog.versionCmp("1.0", "1.1") < 0);
    try std.testing.expect(catalog.versionCmp("1.10", "1.9") > 0);
    try std.testing.expect(catalog.versionCmp("1.0~rc1", "1.0") < 0);
    try std.testing.expect(catalog.versionCmp("2:1.0", "1:9.0") > 0);
    try std.testing.expect(catalog.versionCmp("1.0-1", "1.0-2") < 0);
    try std.testing.expectEqual(@as(i8, 0), catalog.versionCmp("1.0", "1.00"));
}

test "status keeps installed packages and marks orphans and updates" {
    var cat = try catalog.parse(std.testing.allocator, .{
        .status = status,
        .extended = extended,
        .candidates = "curl 8.5.0\n",
        .io = std.testing.io,
    });
    defer cat.deinit();
    try std.testing.expectEqual(@as(usize, 3), cat.items.len);
    try std.testing.expectEqualStrings("8.5.0", find(&cat, "curl").?.upgrade);
    try std.testing.expect(!find(&cat, "curl").?.auto);
    try std.testing.expect(find(&cat, "libfoo").?.orphan);
    try std.testing.expect(!find(&cat, "libc6").?.orphan);
    try std.testing.expect(catalog.accept(find(&cat, "curl").?.*, .programs, ""));
    try std.testing.expect(!catalog.accept(find(&cat, "libfoo").?.*, .programs, ""));
    try std.testing.expect(catalog.fieldMentions("libc6 (>= 2.34), libfoo | other", "libfoo"));
}

test "the list hides automatic libraries until Todos, and search narrows it" {
    var state: app_view.State = .init(std.testing.allocator, std.testing.io);
    defer state.deinit();
    state.fixture = status;
    state.fixture_auto = extended;
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&state, app_view.State.view), .{ .width = 1100, .height = 720 });
    defer t.deinit();
    try std.testing.expect(t.hasText("CPU"));
    try std.testing.expect(t.hasText("RAM"));
    try std.testing.expect(t.hasText("Disco"));
    try std.testing.expect(t.containsText(meta.version));
    try std.testing.expect(t.containsText(meta.date));
    try std.testing.expect(t.hasText("/tmp"));
    try std.testing.expect(t.hasText("/var/log"));
    try t.clickText("Programas");
    try std.testing.expect(t.hasText("curl"));
    try std.testing.expect(!t.hasText("libfoo"));
    try t.clickText("curl");
    try std.testing.expect(t.hasText("Transferir URLs"));
    try t.clickText("Todos");
    try std.testing.expect(t.hasText("libfoo"));
    try t.clickText("Buscar pacotes");
    t.typeText("ausente");
    try std.testing.expect(t.hasText("Nenhum pacote neste filtro"));
    // The open detail keeps the selected package while the list is empty.
    try std.testing.expect(t.hasText("Transferir URLs"));
}

test "cpu deltas, memory lines and rotated logs" {
    const idle = resources.Times{ .busy = 10, .total = 110 };
    const busy = resources.Times{ .busy = 60, .total = 160 };
    try std.testing.expectApproxEqAbs(@as(f32, 1), resources.usage(idle, busy), 0.001);
    const mem = resources.parseMeminfo(
        \\MemTotal:       2048 kB
        \\MemAvailable:   1024 kB
        \\SwapTotal:      512 kB
        \\SwapFree:       256 kB
        \\
    );
    try std.testing.expectEqual(@as(u64, 2048 * 1024), mem.total);
    try std.testing.expectEqual(@as(u64, 1024 * 1024), mem.avail);
    const stat = resources.parseStat(
        \\cpu  10 0 10 80 0 0 0 0
        \\cpu0 5 0 5 40 0 0 0 0
        \\cpu1 5 0 5 40 0 0 0 0
        \\intr 1
        \\
    );
    try std.testing.expectEqual(@as(usize, 2), stat.n);
    try std.testing.expectEqual(@as(u64, 100), stat.all.total);
    try std.testing.expect(resources.rotatedLog("syslog.1"));
    try std.testing.expect(resources.rotatedLog("dpkg.log.2.gz"));
    try std.testing.expect(!resources.rotatedLog("syslog"));
    try std.testing.expectApproxEqAbs(@as(f32, 0.42), resources.parseLoad("0.42 0.10 0.05 1/2 3\n"), 0.001);
}

test "cleaning tmp keeps session sockets and cleaning logs keeps the live file" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;
    const cwd = std.Io.Dir.cwd();
    const root = ".zig-cache/tmp/wslpanel-clean";
    cwd.deleteTree(io, root) catch {};
    try cwd.createDirPath(io, root ++ "/.X11-unix");
    try cwd.writeFile(io, .{ .sub_path = root ++ "/junk", .data = "junk" });
    try cwd.writeFile(io, .{ .sub_path = root ++ "/.X11-unix/X0", .data = "x" });
    const tmp = try resources.clean(gpa, io, root, .tmp);
    try std.testing.expectEqual(@as(usize, 1), tmp.removed);
    _ = try cwd.statFile(io, root ++ "/.X11-unix/X0", .{});
    try std.testing.expectError(error.FileNotFound, cwd.statFile(io, root ++ "/junk", .{}));

    try cwd.createDirPath(io, root ++ "/apt");
    try cwd.writeFile(io, .{ .sub_path = root ++ "/syslog", .data = "live" });
    try cwd.writeFile(io, .{ .sub_path = root ++ "/syslog.1", .data = "old" });
    try cwd.writeFile(io, .{ .sub_path = root ++ "/apt/history.log.2.gz", .data = "gz" });
    const logs = try resources.clean(gpa, io, root, .logs);
    try std.testing.expectEqual(@as(usize, 2), logs.removed);
    _ = try cwd.statFile(io, root ++ "/syslog", .{});
    try std.testing.expectError(error.FileNotFound, cwd.statFile(io, root ++ "/syslog.1", .{}));
    try std.testing.expectError(error.FileNotFound, cwd.statFile(io, root ++ "/apt/history.log.2.gz", .{}));
    cwd.deleteTree(io, root) catch {};
}

test "the footer language buttons switch pt_BR, en and es" {
    var state: app_view.State = .init(std.testing.allocator, std.testing.io);
    defer state.deinit();
    state.fixture = status;
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&state, app_view.State.view), .{ .width = 1100, .height = 720 });
    defer t.deinit();
    try std.testing.expect(t.hasText("Painel do WSL"));
    try std.testing.expect(t.hasText("Limpar /tmp"));
    try t.clickText("EN");
    try std.testing.expect(t.hasText("WSL Panel"));
    try std.testing.expect(t.hasText("Disk"));
    try std.testing.expect(t.hasText("Clean /tmp"));
    try t.clickText("ES");
    try std.testing.expect(t.hasText("Panel de WSL"));
    try std.testing.expect(t.hasText("Limpiar /tmp"));
    try t.clickText("PT");
    try std.testing.expect(t.hasText("Painel do WSL"));
    try std.testing.expect(t.hasText("Limpar /tmp"));
}

test "locale codes map to the three languages" {
    try std.testing.expectEqual(i18n.Lang.pt_BR, i18n.parse("pt_BR.UTF-8").?);
    try std.testing.expectEqual(i18n.Lang.es, i18n.parse("es_MX.UTF-8").?);
    try std.testing.expectEqual(i18n.Lang.en, i18n.parse("en_US.UTF-8").?);
    try std.testing.expect(i18n.parse("C") == null);
    try std.testing.expect(i18n.parse("POSIX") == null);
    try std.testing.expectEqualStrings("Disco", i18n.t(.pt_BR, .disk));
    try std.testing.expectEqualStrings("Disk", i18n.t(.en, .disk));
    try std.testing.expectEqualStrings("Disco", i18n.t(.es, .disk));
    try std.testing.expect(meta.version.len > 0);
    try std.testing.expectEqual(@as(usize, 10), meta.date.len);
}

fn find(cat: *catalog.Catalog, name: []const u8) ?*catalog.Package {
    for (cat.items) |*p| if (std.mem.eql(u8, p.name, name)) return p;
    return null;
}
