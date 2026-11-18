//! Containers, when the docker client exists. CPU and memory come from the
//! cgroup (system.slice or /sys/fs/cgroup/docker), not from `docker stats`,
//! which blocks for seconds. Names come from `docker ps`.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const i18n = @import("i18n.zig");
const resources = @import("resources.zig");

const max_rows = 64;

pub const Ps = struct { id: []const u8, name: []const u8, status: []const u8 };

pub const Container = struct {
    id: [16]u8 = undefined,
    id_len: u8 = 0,
    name: [64]u8 = undefined,
    name_len: u8 = 0,
    status: [48]u8 = undefined,
    status_len: u8 = 0,
    cpu: f32 = 0,
    mem: u64 = 0,
    pids: u32 = 0,
    usage: u64 = 0,
    seen: bool = false,
    /// Set when this sample already took a cgroup. The second tree must not
    /// replace that delta with a zero one.
    fresh: bool = false,

    pub fn idSlice(c: *const Container) []const u8 {
        return c.id[0..c.id_len];
    }
    pub fn nameSlice(c: *const Container) []const u8 {
        return c.name[0..c.name_len];
    }
    pub fn statusSlice(c: *const Container) []const u8 {
        return c.status[0..c.status_len];
    }
};

const Prev = struct { id: [16]u8 = undefined, id_len: u8 = 0, usage: u64 = 0, seen: bool = false };

pub const Board = struct {
    items: std.ArrayList(Container) = .empty,
    have: bool = false,
    down: bool = false,
    last_fast: f64 = -1000,
    last_names: f64 = -1000,

    pub fn deinit(b: *Board, gpa: std.mem.Allocator) void {
        b.items.deinit(gpa);
    }

    pub fn panel(b: *Board, c: *ui.Context, io: std.Io, gpa: std.mem.Allocator, lang: i18n.Lang) void {
        b.sample(io, gpa, c.time);
        c.frameIn(1);
        const col = ui.div(c).column().grow().wFull().px(20).gap(8);
        defer col.end();
        const tools = ui.div(c).row().wFull().gap(8).itemsCenter();
        ui.text(c, i18n.dockerCount(c.alloc(), lang, b.items.items.len), .{ .size = 12, .color = c.theme.muted });
        tools.end();
        if (b.down) {
            ui.text(c, i18n.t(lang, .docker_down), .{ .color = c.theme.danger, .wrap = true });
            return;
        }
        if (b.items.items.len == 0) {
            ui.text(c, i18n.t(lang, .docker_empty), .{ .color = c.theme.muted });
            return;
        }
        b.rows(c, lang);
    }

    fn rows(b: *Board, c: *ui.Context, lang: i18n.Lang) void {
        const head = ui.div(c).row().wFull().px(12).gap(8).itemsCenter();
        const head_name = ui.div(c).row().grow();
        ui.text(c, i18n.t(lang, .proc_name), .{ .size = 12, .color = c.theme.muted });
        head_name.end();
        colHead(c, i18n.t(lang, .cpu), 64);
        colHead(c, i18n.t(lang, .ram), 88);
        colHead(c, "PIDs", 56);
        colHead(c, i18n.t(lang, .proc_state), 180);
        head.end();
        var list = ui.list(c, .{ .count = b.items.items.len, .row_height = 36, .gap = 2, .padding = ui.Edges.all(4) });
        defer list.end();
        while (list.next()) |n| {
            const p = &b.items.items[n];
            var line = ui.div(c).row().wFull().h(36).px(12).itemsCenter().gap(10).rounded(8);
            line = line.hover(c.theme.surface_hover);
            const name = ui.div(c).row().grow().itemsCenter();
            ui.text(c, p.nameSlice(), .{ .size = 13, .weight = .semibold, .truncate = .ellipsis });
            name.end();
            colText(c, cpuText(c, p.cpu), 64);
            colText(c, resources.formatBytes(c, p.mem), 88);
            colText(c, c.print("{d}", .{p.pids}), 56);
            const state = ui.div(c).row().w(180).justifyEnd();
            ui.text(c, p.statusSlice(), .{ .size = 12, .color = c.theme.muted, .truncate = .ellipsis });
            state.end();
            line.end();
        }
    }

    fn sample(b: *Board, io: std.Io, gpa: std.mem.Allocator, now: f64) void {
        if (b.have and now - b.last_fast < 0.9) return;
        const dt = if (b.have) now - b.last_fast else 0;
        b.last_fast = now;
        if (!b.have or now - b.last_names >= 3) {
            var prev: [max_rows]Prev = undefined;
            const n = snap(b, &prev);
            b.last_names = now;
            b.down = !loadNames(b, io, gpa);
            if (!b.down) restore(b, prev[0..n]);
        }
        if (!b.down) readCgroups(b, io, dt);
        std.mem.sort(Container, b.items.items, {}, less);
        b.have = true;
    }
};

pub fn present(io: std.Io) bool {
    if (isFile(io, "/usr/bin/docker")) return true;
    if (isFile(io, "/usr/local/bin/docker")) return true;
    if (isFile(io, "/bin/docker")) return true;
    const raw = std.c.getenv("PATH") orelse return false;
    var it = std.mem.tokenizeAny(u8, std.mem.span(raw), ":");
    while (it.next()) |dir| {
        if (dir.len == 0) continue;
        var buf: [512]u8 = undefined;
        const full = std.fmt.bufPrint(&buf, "{s}/docker", .{dir}) catch continue;
        if (isFile(io, full)) return true;
    }
    return false;
}

pub fn parsePs(line: []const u8) ?Ps {
    const s = std.mem.trim(u8, line, " \t\r\n");
    const a = std.mem.indexOfScalar(u8, s, '\t') orelse return null;
    const rest = s[a + 1 ..];
    const b = std.mem.indexOfScalar(u8, rest, '\t') orelse return null;
    if (a == 0 or b == 0 or b + 1 > rest.len) return null;
    return .{ .id = s[0..a], .name = rest[0..b], .status = rest[b + 1 ..] };
}

/// Percent of one core. `prev == 0` with `seen` false is the caller's job:
/// the first sample only stores the counter.
pub fn cpuShare(prev_usec: u64, next_usec: u64, dt: f64) f32 {
    if (!(dt > 0) or next_usec < prev_usec) return 0;
    const delta: f64 = @floatFromInt(next_usec - prev_usec);
    const pct = (delta / 1_000_000.0) / dt * 100.0;
    if (pct < 0) return 0;
    if (pct > 999) return 999;
    return @floatCast(pct);
}

pub fn scopeId(name: []const u8) ?[]const u8 {
    const prefix = "docker-";
    const suffix = ".scope";
    if (!std.mem.startsWith(u8, name, prefix) or !std.mem.endsWith(u8, name, suffix)) return null;
    const id = name[prefix.len .. name.len - suffix.len];
    if (id.len < 12 or !hex(id)) return null;
    return id;
}

fn loadNames(b: *Board, io: std.Io, gpa: std.mem.Allocator) bool {
    const r = std.process.run(gpa, io, .{
        .argv = &.{ "docker", "ps", "--format", "{{.ID}}\t{{.Names}}\t{{.Status}}" },
        .stdout_limit = .limited(1 << 16),
        .stderr_limit = .limited(4096),
    }) catch return false;
    defer gpa.free(r.stdout);
    defer gpa.free(r.stderr);
    if (!r.term.success()) return false;
    b.items.clearRetainingCapacity();
    var it = std.mem.splitScalar(u8, r.stdout, '\n');
    while (it.next()) |line| {
        if (b.items.items.len >= max_rows) break;
        const ps = parsePs(line) orelse continue;
        var row: Container = .{};
        row.id_len = put(&row.id, ps.id);
        row.name_len = put(&row.name, ps.name);
        row.status_len = put(&row.status, ps.status);
        if (row.id_len == 0 or row.name_len == 0) continue;
        b.items.append(gpa, row) catch break;
    }
    return true;
}

fn readCgroups(b: *Board, io: std.Io, dt: f64) void {
    for (b.items.items) |*row| row.fresh = false;
    readTree(b, io, "/sys/fs/cgroup/system.slice", dt);
    readTree(b, io, "/sys/fs/cgroup/docker", dt);
}

fn readTree(b: *Board, io: std.Io, path: []const u8, dt: f64) void {
    var dir = std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true }) catch return;
    defer dir.close(io);
    var it = dir.iterate();
    while (it.next(io) catch null) |ent| {
        var name_buf: [96]u8 = undefined;
        if (ent.name.len > name_buf.len) continue;
        @memcpy(name_buf[0..ent.name.len], ent.name);
        const name = name_buf[0..ent.name.len];
        const id = scopeId(name) orelse bareId(name) orelse continue;
        const row = find(b, id) orelse continue;
        if (row.fresh) continue;
        var path_buf: [192]u8 = undefined;
        const usage = readUsage(io, path, name, &path_buf) orelse continue;
        const mem = readNum(io, path, name, "memory.current", &path_buf) orelse 0;
        const pids = readNum(io, path, name, "pids.current", &path_buf) orelse 0;
        if (row.seen) row.cpu = cpuShare(row.usage, usage, dt) else row.cpu = 0;
        row.mem = mem;
        row.pids = @intCast(@min(pids, std.math.maxInt(u32)));
        row.usage = usage;
        row.seen = true;
        row.fresh = true;
    }
}

fn bareId(name: []const u8) ?[]const u8 {
    if (name.len < 12 or name.len > 64 or !hex(name)) return null;
    return name;
}

fn find(b: *Board, id: []const u8) ?*Container {
    for (b.items.items) |*row| {
        const cid = row.idSlice();
        if (cid.len > 0 and std.mem.startsWith(u8, id, cid)) return row;
    }
    return null;
}

fn readNum(io: std.Io, parent: []const u8, name: []const u8, file: []const u8, buf: []u8) ?u64 {
    const path = std.fmt.bufPrint(buf, "{s}/{s}/{s}", .{ parent, name, file }) catch return null;
    var raw: [64]u8 = undefined;
    const text = readSmall(io, path, &raw) orelse return null;
    return parseU64(text);
}

fn readUsage(io: std.Io, parent: []const u8, name: []const u8, buf: []u8) ?u64 {
    const path = std.fmt.bufPrint(buf, "{s}/{s}/cpu.stat", .{ parent, name }) catch return null;
    var raw: [256]u8 = undefined;
    const text = readSmall(io, path, &raw) orelse return null;
    var it = std.mem.tokenizeAny(u8, text, " \t\r\n");
    const key = it.next() orelse return null;
    if (!std.mem.eql(u8, key, "usage_usec")) return null;
    const n = it.next() orelse return null;
    return std.fmt.parseInt(u64, n, 10) catch null;
}

fn snap(b: *Board, out: []Prev) usize {
    const n = @min(b.items.items.len, out.len);
    for (b.items.items[0..n], 0..) |row, i| {
        out[i] = .{ .id_len = row.id_len, .usage = row.usage, .seen = row.seen };
        @memcpy(out[i].id[0..row.id_len], row.id[0..row.id_len]);
    }
    return n;
}

fn restore(b: *Board, prev: []const Prev) void {
    for (b.items.items) |*row| {
        for (prev) |p| {
            if (p.id_len == row.id_len and std.mem.eql(u8, p.id[0..p.id_len], row.idSlice())) {
                row.usage = p.usage;
                row.seen = p.seen;
                break;
            }
        }
    }
}

fn less(_: void, a: Container, b: Container) bool {
    if (a.cpu == b.cpu) return a.mem > b.mem;
    return a.cpu > b.cpu;
}

fn colHead(c: *ui.Context, label: []const u8, width: f32) void {
    const box = ui.div(c).row().w(width).justifyEnd();
    ui.text(c, label, .{ .size = 12, .color = c.theme.muted });
    box.end();
}

fn colText(c: *ui.Context, label: []const u8, width: f32) void {
    const box = ui.div(c).row().w(width).justifyEnd();
    ui.text(c, label, .{ .size = 12, .mono = true, .color = c.theme.muted });
    box.end();
}

fn cpuText(c: *ui.Context, cpu: f32) []const u8 {
    if (cpu < 10) return c.print("{d:.1}%", .{cpu});
    return c.print("{d:.0}%", .{cpu});
}

fn put(dst: []u8, src: []const u8) u8 {
    const n = @min(src.len, dst.len);
    @memcpy(dst[0..n], src[0..n]);
    return @intCast(n);
}

fn parseU64(text: []const u8) ?u64 {
    const s = std.mem.trim(u8, text, " \t\r\n");
    if (s.len == 0 or !std.ascii.isDigit(s[0])) return null;
    return std.fmt.parseInt(u64, s, 10) catch null;
}

fn readSmall(io: std.Io, path: []const u8, buf: []u8) ?[]const u8 {
    var file = std.Io.Dir.cwd().openFile(io, path, .{}) catch return null;
    defer file.close(io);
    const n = file.readPositional(io, &.{buf}, 0) catch return null;
    if (n == 0) return null;
    return buf[0..n];
}

fn isFile(io: std.Io, path: []const u8) bool {
    const st = std.Io.Dir.cwd().statFile(io, path, .{}) catch return false;
    return st.kind == .file or st.kind == .sym_link;
}

fn hex(s: []const u8) bool {
    for (s) |ch| if (!std.ascii.isHex(ch)) return false;
    return true;
}
