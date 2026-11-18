//! Processes of this distro, from /proc: name, state, CPU share and RSS.
//! Ending one sends SIGTERM. Pid 1 and this panel are not offered.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const i18n = @import("i18n.zig");
const resources = @import("resources.zig");

pub const page_bytes: u64 = 4096;
const max_procs = 400;

pub const Parsed = struct {
    pid: u32,
    name: []const u8,
    state: u8,
    ticks: u64,
    rss_pages: u64,
};

pub const Proc = struct {
    pid: u32 = 0,
    cpu: f32 = 0,
    rss: u64 = 0,
    state: u8 = '?',
    name: [16]u8 = undefined,
    name_len: u8 = 0,

    pub fn nameSlice(p: *const Proc) []const u8 {
        return p.name[0..p.name_len];
    }
};

pub const List = struct {
    items: std.ArrayList(Proc) = .empty,
    prev: std.AutoHashMapUnmanaged(u32, u64) = .empty,
    prev_total: u64 = 0,
    have: bool = false,
    last: f64 = -1000,
    query: ui.TextBuffer = .{},
    selected: u32 = 0,
    ask: bool = false,

    pub fn deinit(l: *List, gpa: std.mem.Allocator) void {
        l.items.deinit(gpa);
        l.prev.deinit(gpa);
        l.query.deinit();
    }

    pub fn panel(l: *List, c: *ui.Context, io: std.Io, gpa: std.mem.Allocator, lang: i18n.Lang, toaster: *kit.Toaster) void {
        l.sample(io, gpa, c.time);
        c.frameIn(1);
        const col = ui.div(c).column().grow().wFull().px(20).gap(8);
        defer col.end();
        const tools = ui.div(c).row().wFull().gap(8).itemsCenter();
        const search = ui.div(c).row().grow();
        _ = ui.textField(c, &l.query, .{ .placeholder = i18n.t(lang, .proc_search), .width = .fill });
        search.end();
        ui.text(c, i18n.procCount(c.alloc(), lang, l.items.items.len), .{ .size = 12, .color = c.theme.muted });
        if (l.chosen()) |p| if (killable(p.pid, selfPid())) {
            if (ui.button(c, i18n.t(lang, .proc_kill), .{ .variant = .danger, .size = 13 }).clicked) l.ask = true;
        };
        tools.end();
        l.rows(c, lang);
        l.confirm(c, lang, toaster);
    }

    fn rows(l: *List, c: *ui.Context, lang: i18n.Lang) void {
        const q = l.query.text();
        var shown: std.ArrayList(usize) = .empty;
        defer shown.deinit(c.alloc());
        for (l.items.items, 0..) |p, i| {
            if (q.len > 0 and std.mem.indexOf(u8, p.nameSlice(), q) == null) continue;
            shown.append(c.alloc(), i) catch return;
        }
        const head = ui.div(c).row().wFull().px(12).gap(8).itemsCenter();
        const head_name = ui.div(c).row().grow();
        ui.text(c, i18n.t(lang, .proc_name), .{ .size = 12, .color = c.theme.muted });
        head_name.end();
        colHead(c, "PID", 72);
        colHead(c, "CPU", 48);
        colHead(c, "RSS", 80);
        colHead(c, i18n.t(lang, .proc_state), 52);
        head.end();
        if (shown.items.len == 0) {
            ui.text(c, i18n.t(lang, .proc_empty), .{ .color = c.theme.muted });
            return;
        }
        var list = ui.list(c, .{ .count = shown.items.len, .row_height = 36, .gap = 2, .padding = ui.Edges.all(4) });
        defer list.end();
        while (list.next()) |n| {
            // A pointer into the list, not a copy: the name's bytes have to
            // outlive this frame, and a copy's slice would not.
            const p = &l.items.items[shown.items[n]];
            const on = p.pid == l.selected;
            var line = ui.div(c).row().wFull().h(36).px(12).itemsCenter().gap(10).rounded(8).control();
            if (on) line = line.bg(c.theme.accent.alpha(0.16));
            line = line.hover(c.theme.surface_hover);
            if (line.clicked()) l.selected = p.pid;
            const name = ui.div(c).row().grow().itemsCenter();
            ui.text(c, p.nameSlice(), .{ .size = 13, .weight = .semibold, .truncate = .ellipsis });
            name.end();
            colText(c, c.print("{d}", .{p.pid}), 72);
            colText(c, c.print("{d:.0}%", .{p.cpu * 100}), 48);
            colText(c, resources.formatBytes(c, p.rss), 80);
            colText(c, c.print("{c}", .{p.state}), 52);
            line.end();
        }
    }

    fn confirm(l: *List, c: *ui.Context, lang: i18n.Lang, toaster: *kit.Toaster) void {
        if (!l.ask) return;
        const p = l.chosen();
        var open = true;
        const title = if (p) |proc| i18n.pendingKill(c.alloc(), lang, proc.nameSlice(), proc.pid) else "";
        if (kit.dialog(c, "kill", &open, .{
            .title = i18n.t(lang, .proc_kill),
            .description = title,
            .ok = i18n.t(lang, .confirm),
            .cancel = i18n.t(lang, .cancel),
            .ok_variant = .danger,
        })) |d| {
            switch (d.end()) {
                .ok => if (p) |proc| l.end(lang, toaster, proc.pid),
                .cancel => l.ask = false,
                .none => {
                    if (!open) l.ask = false;
                },
            }
        } else l.ask = false;
    }

    fn end(l: *List, lang: i18n.Lang, toaster: *kit.Toaster, pid: u32) void {
        l.ask = false;
        l.selected = 0;
        const ok = endProc(pid);
        toaster.push(.{
            .status = if (ok) .success else .warning,
            .title = i18n.t(lang, .proc_kill),
            .message = if (ok) i18n.t(lang, .proc_ended) else i18n.t(lang, .proc_denied),
        });
        l.last = -1000;
    }

    fn chosen(l: *List) ?*Proc {
        if (l.selected == 0) return null;
        for (l.items.items) |*p| if (p.pid == l.selected) return p;
        return null;
    }

    fn sample(l: *List, io: std.Io, gpa: std.mem.Allocator, now: f64) void {
        if (l.have and now - l.last < 0.9) return;
        l.last = now;
        const total = machine(io);
        var next: std.AutoHashMapUnmanaged(u32, u64) = .empty;
        l.items.clearRetainingCapacity();
        var dir = std.Io.Dir.cwd().openDir(io, "/proc", .{ .iterate = true }) catch return;
        defer dir.close(io);
        var it = dir.iterate();
        while (it.next(io) catch null) |ent| {
            if (l.items.items.len >= max_procs) break;
            const pid = std.fmt.parseInt(u32, ent.name, 10) catch continue;
            var path: [32]u8 = undefined;
            const sub = std.fmt.bufPrint(&path, "/proc/{d}/stat", .{pid}) catch continue;
            var buf: [512]u8 = undefined;
            const text = readAt(io, sub, &buf) orelse continue;
            const parsed = parseStat(text) orelse continue;
            const prev_ticks = if (l.have) l.prev.get(pid) orelse parsed.ticks else parsed.ticks;
            const cpu = if (l.have and total > l.prev_total)
                resources.usage(.{ .busy = prev_ticks, .total = l.prev_total }, .{ .busy = parsed.ticks, .total = total })
            else
                0;
            next.put(gpa, pid, parsed.ticks) catch {};
            var proc: Proc = .{
                .pid = parsed.pid,
                .cpu = cpu,
                .rss = parsed.rss_pages * page_bytes,
                .state = parsed.state,
            };
            proc.name_len = putName(&proc.name, parsed.name);
            l.items.append(gpa, proc) catch {};
        }
        l.prev.deinit(gpa);
        l.prev = next;
        l.prev_total = total;
        l.have = true;
        std.mem.sort(Proc, l.items.items, {}, less);
        if (l.chosen() == null) l.selected = 0;
    }
};

pub fn killable(pid: u32, self_pid: u32) bool {
    return pid > 1 and pid != self_pid;
}

pub fn endProc(pid: u32) bool {
    if (pid <= 1) return false;
    std.posix.kill(@intCast(pid), std.posix.SIG.TERM) catch return false;
    return true;
}

pub fn parseStat(line: []const u8) ?Parsed {
    const open = std.mem.indexOfScalar(u8, line, '(') orelse return null;
    const close = std.mem.lastIndexOfScalar(u8, line, ')') orelse return null;
    if (close <= open) return null;
    const pid = std.fmt.parseInt(u32, std.mem.trim(u8, line[0..open], " \t"), 10) catch return null;
    var it = std.mem.tokenizeAny(u8, line[close + 1 ..], " \t\n");
    var fields: [24][]const u8 = undefined;
    var n: usize = 0;
    while (it.next()) |tok| {
        if (n >= fields.len) break;
        fields[n] = tok;
        n += 1;
    }
    if (n < 22 or fields[0].len == 0) return null;
    const utime = std.fmt.parseInt(u64, fields[11], 10) catch 0;
    const stime = std.fmt.parseInt(u64, fields[12], 10) catch 0;
    const rss = std.fmt.parseInt(u64, fields[21], 10) catch 0;
    return .{
        .pid = pid,
        .name = line[open + 1 .. close],
        .state = fields[0][0],
        .ticks = utime +| stime,
        .rss_pages = rss,
    };
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

fn less(_: void, a: Proc, b: Proc) bool {
    if (a.cpu == b.cpu) return a.rss > b.rss;
    return a.cpu > b.cpu;
}

fn putName(dst: []u8, src: []const u8) u8 {
    var n: usize = 0;
    for (src) |ch| {
        if (n >= dst.len) break;
        dst[n] = if (ch < 32 or ch == 127) '?' else ch;
        n += 1;
    }
    return @intCast(n);
}

fn selfPid() u32 {
    return @intCast(std.os.linux.getpid());
}

fn machine(io: std.Io) u64 {
    var buf: [1024]u8 = undefined;
    const text = readAt(io, "/proc/stat", &buf) orelse return 0;
    return resources.parseStat(text).all.total;
}

fn readAt(io: std.Io, path: []const u8, buf: []u8) ?[]const u8 {
    var file = std.Io.Dir.cwd().openFile(io, path, .{}) catch return null;
    defer file.close(io);
    const n = file.readPositional(io, &.{buf}, 0) catch return null;
    if (n == 0) return null;
    return buf[0..n];
}
